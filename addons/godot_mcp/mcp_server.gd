@tool
extends Node

var editor_interface: EditorInterface = null
var undo_redo_manager: EditorUndoRedoManager = null
var tcp_server: TCPServer = TCPServer.new()
var port: int = 6505
var peers: Array = []

func _ready():
    start_server()

func start_server():
    var err = tcp_server.listen(port)
    if err != OK:
        push_error("[Godot MCP Server] Failed to start server on port %d, error: %d" % [port, err])
    else:
        print("[Godot MCP Server] TCP Server running on port %d" % port)

func stop_server():
    tcp_server.stop()
    for p in peers:
        p.disconnect_from_host()
    peers.clear()

func _process(_delta):
    if tcp_server.is_connection_available():
        var conn = tcp_server.take_connection()
        if conn:
            peers.append(conn)

    var to_remove = []
    for peer in peers:
        peer.poll()
        var status = peer.get_status()
        if status == StreamPeerTCP.STATUS_CONNECTED:
            var available = peer.get_available_bytes()
            if available > 0:
                var raw_data = peer.get_utf8_string(available)
                handle_raw_message(peer, raw_data)
        elif status != StreamPeerTCP.STATUS_CONNECTING:
            to_remove.append(peer)

    for p in to_remove:
        peers.erase(p)

func handle_raw_message(peer: StreamPeerTCP, raw: String):
    # Parse potential HTTP or WebSocket payload, or direct JSON over socket
    var json_str = raw
    if raw.begins_with("GET ") or raw.begins_with("POST "):
        var body_start = raw.find("\r\n\r\n")
        if body_start != -1:
            json_str = raw.substr(body_start + 4)
        else:
            json_str = ""

    # Also handle simple JSON payloads sent directly or wrapped
    var json = JSON.new()
    var parse_err = json.parse(json_str.strip_edges())
    if parse_err != OK:
        # Check if WebSocket handshaking or ping
        if raw.contains("Upgrade: websocket") or raw.contains("ping"):
            send_raw_response(peer, JSON.stringify({"status": "ok", "version": "2.0.0"}))
        return

    var data = json.get_data()
    if typeof(data) != TYPE_DICTIONARY:
        return

    var req_id = data.get("id", "req_unknown")
    var command = data.get("command", "")
    var params = data.get("params", {})

    var result = process_command(command, params)
    send_response(peer, req_id, result)

func send_raw_response(peer: StreamPeerTCP, msg: String):
    peer.put_data(msg.to_utf8_buffer())

func send_response(peer: StreamPeerTCP, req_id: String, res: Dictionary):
    var payload = {
        "id": req_id,
        "status": res.get("status", "ok"),
        "result": res.get("result", null),
        "error": res.get("error", null)
    }
    var json_out = JSON.stringify(payload)
    var http_resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: %d\r\n\r\n%s" % [json_out.length(), json_out]
    peer.put_data(http_resp.to_utf8_buffer())

func process_command(cmd: String, params: Dictionary) -> Dictionary:
    match cmd:
        "ping":
            return {"status": "ok", "result": {"version": "2.0.0", "mode": "in_editor"}}
        "get_scene_tree":
            return get_scene_tree_in_editor()
        "add_node":
            return add_node_in_editor(params)
        "modify_node_properties":
            return modify_node_properties_in_editor(params)
        "delete_node":
            return delete_node_in_editor(params)
        "reparent_node":
            return reparent_node_in_editor(params)
        "edit_script":
            return edit_script_in_editor(params)
        "simulate_input":
            return simulate_input_event(params)
        "take_screenshot":
            return take_viewport_screenshot()
        _:
            return {"status": "error", "error": "Unknown in-editor command: " + cmd}

func get_scene_tree_in_editor() -> Dictionary:
    if not editor_interface:
        return {"status": "error", "error": "EditorInterface not available"}
    var root = editor_interface.get_edited_scene_root()
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var tree_data = serialize_node(root)
    return {"status": "ok", "result": tree_data}

func serialize_node(node: Node) -> Dictionary:
    var children_data = []
    for child in node.get_children():
        children_data.append(serialize_node(child))

    return {
        "name": node.name,
        "class": node.get_class(),
        "path": String(node.get_path()),
        "children": children_data
    }

func add_node_in_editor(params: Dictionary) -> Dictionary:
    if not editor_interface:
        return {"status": "error", "error": "EditorInterface not available"}
    var root = editor_interface.get_edited_scene_root()
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_type = params.get("type", "Node")
    var node_name = params.get("name", node_type)
    var parent_path = params.get("parent_path", "")

    var parent_node: Node = root
    if parent_path != "" and parent_path != ".":
        parent_node = root.get_node_or_null(parent_path)
        if not parent_node:
            return {"status": "error", "error": "Parent node not found: " + parent_path}

    if not ClassDB.class_exists(node_type):
        return {"status": "error", "error": "Invalid node class type: " + node_type}

    var new_node = ClassDB.instantiate(node_type) as Node
    new_node.name = node_name

    # Use EditorUndoRedoManager for Undo/Redo support!
    if undo_redo_manager:
        undo_redo_manager.create_action("Add Node " + node_name)
        undo_redo_manager.add_do_method(parent_node, "add_child", new_node)
        undo_redo_manager.add_do_method(new_node, "set_owner", root)
        undo_redo_manager.add_do_reference(new_node)
        undo_redo_manager.add_undo_method(parent_node, "remove_child", new_node)
        undo_redo_manager.commit_action()
    else:
        parent_node.add_child(new_node)
        new_node.owner = root

    return {"status": "ok", "result": {"path": String(new_node.get_path()), "name": new_node.name}}

func modify_node_properties_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var props = params.get("properties", {})
    var target_node = root.get_node_or_null(node_path)
    if not target_node:
        return {"status": "error", "error": "Target node not found: " + node_path}

    for prop_name in props:
        var val = parse_variant(props[prop_name])
        if undo_redo_manager:
            var old_val = target_node.get(prop_name)
            undo_redo_manager.create_action("Set Property " + prop_name)
            undo_redo_manager.add_do_property(target_node, prop_name, val)
            undo_redo_manager.add_undo_property(target_node, prop_name, old_val)
            undo_redo_manager.commit_action()
        else:
            target_node.set(prop_name, val)

    return {"status": "ok", "result": {"updated": props.keys()}}

func delete_node_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open"}

    var node_path = params.get("node_path", "")
    var target_node = root.get_node_or_null(node_path)
    if not target_node or target_node == root:
        return {"status": "error", "error": "Invalid target node for deletion: " + node_path}

    var parent = target_node.get_parent()
    if undo_redo_manager:
        undo_redo_manager.create_action("Delete Node " + target_node.name)
        undo_redo_manager.add_do_method(parent, "remove_child", target_node)
        undo_redo_manager.add_undo_method(parent, "add_child", target_node)
        undo_redo_manager.add_undo_reference(target_node)
        undo_redo_manager.commit_action()
    else:
        target_node.queue_free()

    return {"status": "ok", "result": "Node deleted"}

func reparent_node_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open"}

    var node_path = params.get("node_path", "")
    var new_parent_path = params.get("new_parent_path", "")

    var target_node = root.get_node_or_null(node_path)
    var new_parent = root.get_node_or_null(new_parent_path)

    if not target_node or not new_parent:
        return {"status": "error", "error": "Node or new parent not found"}

    target_node.reparent(new_parent)
    return {"status": "ok", "result": {"new_path": String(target_node.get_path())}}

func edit_script_in_editor(params: Dictionary) -> Dictionary:
    var script_path = params.get("script_path", "")
    var code = params.get("code", "")
    if script_path == "":
        return {"status": "error", "error": "Missing script_path"}

    var file = FileAccess.open(script_path, FileAccess.WRITE)
    if not file:
        return {"status": "error", "error": "Cannot open file for writing: " + script_path}

    file.store_string(code)
    file.close()

    if editor_interface:
        editor_interface.get_resource_filesystem().scan()

    return {"status": "ok", "result": "Script updated successfully"}

func simulate_input_event(params: Dictionary) -> Dictionary:
    var event_type = params.get("type", "action")
    var action_name = params.get("action", "")

    if event_type == "action" and action_name != "":
        var ev = InputEventAction.new()
        ev.action = action_name
        ev.pressed = params.get("pressed", true)
        Input.parse_input_event(ev)
        return {"status": "ok", "result": "Input action simulated: " + action_name}

    return {"status": "error", "error": "Unsupported input simulation parameters"}

func take_viewport_screenshot() -> Dictionary:
    if not editor_interface:
        return {"status": "error", "error": "EditorInterface not available"}

    var vp = editor_interface.get_viewport()
    if not vp:
        return {"status": "error", "error": "Viewport unavailable"}

    var tex = vp.get_texture()
    var img = tex.get_image()
    var buffer = img.save_png_to_buffer()
    var b64 = Marshalls.raw_to_base64(buffer)

    return {"status": "ok", "result": {"image_base64": b64, "mime_type": "image/png"}}

func parse_variant(val):
    if typeof(val) == TYPE_DICTIONARY and val.has("__type"):
        var t = val["__type"]
        match t:
            "Vector2":
                return Vector2(val.get("x", 0), val.get("y", 0))
            "Vector3":
                return Vector3(val.get("x", 0), val.get("y", 0), val.get("z", 0))
            "Color":
                return Color(val.get("r", 0), val.get("g", 0), val.get("b", 0), val.get("a", 1))
            "Rect2":
                return Rect2(val.get("x", 0), val.get("y", 0), val.get("width", 0), val.get("height", 0))
    return val
