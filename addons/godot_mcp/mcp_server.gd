@tool
extends Node

var editor_interface: EditorInterface = null
var undo_redo_manager: EditorUndoRedoManager = null
var dock_instance = null
var debugger_plugin = null
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
        "get_godot_version":
            return {"status": "ok", "result": Engine.get_version_info()}

        # --- Deep Integration Commands ---
        "get_editor_selection":
            return get_editor_selection_in_editor(params)
        "set_editor_selection":
            return set_editor_selection_in_editor(params)
        "focus_editor_viewport_3d":
            return focus_editor_viewport_3d_in_editor(params)
        "get_active_script_editor":
            return get_active_script_editor_in_editor(params)
        "get_debugger_errors":
            return get_debugger_errors_in_editor(params)
        "clear_debugger_errors":
            return clear_debugger_errors_in_editor(params)
        "get_debugger_error_counts":
            return get_debugger_error_counts_in_editor(params)

        "execute_gdscript":
            return execute_gdscript_in_editor(params)
        "read_resource":
            return read_resource_in_editor(params)
        "modify_resource":
            return modify_resource_in_editor(params)
        "create_scene":
            return create_scene_in_editor(params)
        "get_scene_tree":
            return get_scene_tree_in_editor(params)
        "add_node":
            return add_node_in_editor(params)
        "modify_node_properties":
            return modify_node_properties_in_editor(params)
        "delete_node":
            return delete_node_in_editor(params)
        "reparent_node":
            return reparent_node_in_editor(params)
        "duplicate_node":
            return duplicate_node_in_editor(params)
        "inspect_node":
            return inspect_node_in_editor(params)
        "instantiate_scene":
            return instantiate_scene_in_editor(params)
        "create_script":
            return create_script_in_editor(params)
        "attach_script":
            return attach_script_in_editor(params)
        "edit_script":
            return edit_script_in_editor(params)
        "validate_script":
            return validate_script_in_editor(params)
        "analyze_gdscript_ast":
            return analyze_gdscript_ast_in_editor(params)
        "find_script_references":
            return find_script_references_in_editor(params)
        "connect_signal":
            return connect_signal_in_editor(params)
        "disconnect_signal":
            return disconnect_signal_in_editor(params)
        "list_signals":
            return list_signals_in_editor(params)
        "configure_audio_bus":
            return configure_audio_bus_in_editor(params)
        "create_audio_stream_player":
            return create_audio_stream_player_in_editor(params)
        "simulate_input":
            return simulate_input_event(params)
        "take_screenshot":
            return take_viewport_screenshot(params)
        "get_uid":
            return get_uid_in_editor(params)
        "update_project_uids":
            return update_project_uids_in_editor(params)
        "export_mesh_library":
            return export_mesh_library_in_editor(params)
        "install_editor_plugin":
            return install_editor_plugin_in_editor(params)
        "create_shader_material":
            return create_shader_material_in_editor(params)
        "set_shader_parameter":
            return set_shader_parameter_in_editor(params)
        "create_visual_shader":
            return create_visual_shader_in_editor(params)
        "set_tilemap_cell":
            return set_tilemap_cell_in_editor(params)
        "configure_navigation_region":
            return configure_navigation_region_in_editor(params)
        "set_gridmap_cell":
            return set_gridmap_cell_in_editor(params)
        "create_animation":
            return create_animation_in_editor(params)
        "add_animation_track":
            return add_animation_track_in_editor(params)
        "insert_animation_keyframe":
            return insert_animation_keyframe_in_editor(params)
        "configure_animation_tree":
            return configure_animation_tree_in_editor(params)
        "configure_physics_body":
            return configure_physics_body_in_editor(params)
        "add_collision_shape":
            return add_collision_shape_in_editor(params)
        "configure_raycast":
            return configure_raycast_in_editor(params)
        "configure_area":
            return configure_area_in_editor(params)
        "create_ui_layout":
            return create_ui_layout_in_editor(params)
        "apply_theme":
            return apply_theme_in_editor(params)
        "configure_control_anchors":
            return configure_control_anchors_in_editor(params)
        "set_control_theme_override":
            return set_control_theme_override_in_editor(params)
        "replay_input_sequence":
            return replay_input_sequence(params)
        "import_asset":
            return import_asset_in_editor(params)
        "get_performance_metrics":
            return get_performance_metrics_in_editor(params)
        "get_memory_breakdown":
            return get_memory_breakdown_in_editor(params)
        "create_behavior_tree":
            return create_behavior_tree_in_editor(params)
        "configure_blackboard":
            return configure_blackboard_in_editor(params)
        _:
            return {"status": "error", "error": "Unknown in-editor command: " + cmd}

func create_scene_in_editor(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var root_type = params.get("root_type", "Node2D")
    var root_name = params.get("root_name", "Root")
    var inherits = params.get("inherits", "")

    if scene_path == "":
        return {"status": "error", "error": "Missing scene_path"}

    var root: Node = null
    if inherits != "":
        if not FileAccess.file_exists(inherits):
            return {"status": "error", "error": "Base scene to inherit not found: " + inherits}
        var base_packed = ResourceLoader.load(inherits) as PackedScene
        if not base_packed:
            return {"status": "error", "error": "Failed to load base scene at: " + inherits}
        root = base_packed.instantiate()
        if root_name != "" and root_name != "Root":
            root.name = root_name
    else:
        if not ClassDB.class_exists(root_type):
            return {"status": "error", "error": "Invalid root_type: " + root_type}
        root = ClassDB.instantiate(root_type) as Node
        root.name = root_name

    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(root)
    if result != OK:
        return {"status": "error", "error": "Failed to pack scene: %d" % result}

    var err = ResourceSaver.save(packed_scene, scene_path)
    if err != OK:
        return {"status": "error", "error": "Failed to save scene to '%s': %d" % [scene_path, err]}

    if editor_interface:
        editor_interface.get_resource_filesystem().scan()

    return {"status": "ok", "result": {"scene_path": scene_path, "root_name": root.name, "root_type": root.get_class(), "inherits": inherits}}

func get_scene_tree_in_editor(params: Dictionary = {}) -> Dictionary:
    if not editor_interface:
        return {"status": "error", "error": "EditorInterface not available"}
    var root = editor_interface.get_edited_scene_root()
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var max_depth = int(params.get("max_depth", -1))
    var filter_type = String(params.get("filter_type", ""))

    var tree_data = serialize_node(root, 0, max_depth, filter_type)
    return {"status": "ok", "result": tree_data}

func serialize_node(node: Node, current_depth: int = 0, max_depth: int = -1, filter_type: String = "") -> Dictionary:
    var children_data = []
    if max_depth < 0 or current_depth < max_depth:
        for child in node.get_children():
            var child_dict = serialize_node(child, current_depth + 1, max_depth, filter_type)
            if not child_dict.is_empty():
                children_data.append(child_dict)

    var matches_filter = true
    if filter_type != "":
        matches_filter = node.is_class(filter_type) or node.get_class() == filter_type

    if not matches_filter and children_data.is_empty():
        return {}

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

    var node_type = params.get("node_type", params.get("type", "Node"))
    var node_name = params.get("node_name", params.get("name", node_type))
    var parent_path = params.get("parent_path", "")
    var props = params.get("properties", {})
    var script_path = params.get("script_path", "")

    var parent_node: Node = root
    if parent_path != "" and parent_path != ".":
        parent_node = root.get_node_or_null(parent_path)
        if not parent_node:
            return {"status": "error", "error": "Parent node not found: " + parent_path}

    if not ClassDB.class_exists(node_type):
        return {"status": "error", "error": "Invalid node class type: " + node_type}

    var new_node = ClassDB.instantiate(node_type) as Node
    new_node.name = node_name

    if script_path != "":
        if FileAccess.file_exists(script_path):
            var scr = ResourceLoader.load(script_path) as Script
            if scr:
                new_node.set_script(scr)
        else:
            return {"status": "error", "error": "Script file not found at: " + script_path}

    for p in props:
        new_node.set(p, parse_variant(props[p]))

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
    var target_node = root if node_path == "." else root.get_node_or_null(node_path)
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

    return {"status": "ok", "result": {"updated": props.keys(), "node_path": String(target_node.get_path())}}

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
    var new_parent_path = params.get("new_parent_path", ".")
    var keep_global = params.get("keep_global_transform", true)

    var target_node = root.get_node_or_null(node_path)
    var new_parent = root if new_parent_path == "." else root.get_node_or_null(new_parent_path)

    if not target_node or not new_parent:
        return {"status": "error", "error": "Node or new parent not found"}

    target_node.reparent(new_parent, keep_global)
    return {"status": "ok", "result": {"new_path": String(target_node.get_path())}}

func duplicate_node_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var new_name = params.get("new_name", "")
    var parent_path = params.get("parent_path", "")

    var target_node = root if node_path == "." else root.get_node_or_null(node_path)
    if not target_node:
        return {"status": "error", "error": "Target node not found for duplication"}

    var dest_parent = target_node.get_parent()
    if parent_path != "":
        dest_parent = root if parent_path == "." else root.get_node_or_null(parent_path)
        if not dest_parent:
            return {"status": "error", "error": "Destination parent node not found: " + parent_path}

    var dup = target_node.duplicate()
    if new_name != "":
        dup.name = new_name

    if undo_redo_manager:
        undo_redo_manager.create_action("Duplicate Node " + target_node.name)
        undo_redo_manager.add_do_method(dest_parent, "add_child", dup)
        undo_redo_manager.add_do_method(dup, "set_owner", root)
        undo_redo_manager.add_do_reference(dup)
        undo_redo_manager.add_undo_method(dest_parent, "remove_child", dup)
        undo_redo_manager.commit_action()
    else:
        dest_parent.add_child(dup)
        dup.owner = root

    return {"status": "ok", "result": {"duplicated_node": dup.name, "path": String(dup.get_path())}}

func inspect_node_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var include_signals = params.get("include_signals", true)
    var include_groups = params.get("include_groups", true)
    var include_children = params.get("include_children", true)

    var target = root if (node_path == "." or node_path == "" or (root and node_path == root.name)) else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Target node not found: " + node_path}

    var props = {}
    for p in target.get_property_list():
        var pname = p["name"]
        props[pname] = target.get(pname)

    var res = {
        "name": target.name,
        "class": target.get_class(),
        "path": String(target.get_path()),
        "properties": props,
        "children_count": target.get_child_count()
    }

    if target.get_script():
        res["script_path"] = target.get_script().resource_path

    if include_signals:
        var sigs = []
        for s in target.get_signal_list():
            sigs.append({"name": s["name"], "args": s["args"]})
        res["signals"] = sigs

    if include_groups:
        var grps = []
        for g in target.get_groups():
            grps.append(String(g))
        res["groups"] = grps

    if include_children:
        var children_list = []
        for c in target.get_children():
            children_list.append({"name": c.name, "class": c.get_class(), "path": String(c.get_path())})
        res["children"] = children_list

    return {"status": "ok", "result": res}

func instantiate_scene_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var target_scene_path = params.get("target_scene_path", params.get("subscene_path", ""))
    var parent_path = params.get("parent_path", ".")
    var node_name = params.get("node_name", "")

    if target_scene_path == "" or not FileAccess.file_exists(target_scene_path):
        return {"status": "error", "error": "Invalid or missing target_scene_path: " + target_scene_path}

    var subscene_packed = ResourceLoader.load(target_scene_path) as PackedScene
    if not subscene_packed:
        return {"status": "error", "error": "Failed to load sub-scene at " + target_scene_path}

    var parent = root if (parent_path == "." or parent_path == "") else root.get_node_or_null(parent_path)
    if not parent:
        return {"status": "error", "error": "Parent node not found at path: " + parent_path}

    var inst = subscene_packed.instantiate()
    if node_name != "":
        inst.name = node_name

    if params.has("position"):
        var pos_val = parse_variant(params["position"])
        if typeof(pos_val) in [TYPE_VECTOR2, TYPE_VECTOR3]:
            inst.set("position", pos_val)

    if undo_redo_manager:
        undo_redo_manager.create_action("Instantiate Scene " + inst.name)
        undo_redo_manager.add_do_method(parent, "add_child", inst)
        undo_redo_manager.add_do_method(inst, "set_owner", root)
        undo_redo_manager.add_do_reference(inst)
        undo_redo_manager.add_undo_method(parent, "remove_child", inst)
        undo_redo_manager.commit_action()
    else:
        parent.add_child(inst)
        inst.owner = root

    return {
        "status": "ok",
        "result": {
            "node_name": inst.name,
            "node_path": String(inst.get_path()),
            "target_scene_path": target_scene_path
        }
    }

func create_script_in_editor(params: Dictionary) -> Dictionary:
    var script_path = params.get("script_path", "")
    if script_path == "":
        return {"status": "error", "error": "Missing script_path"}

    var extends_class = params.get("extends_class", "Node")
    var class_name_str = params.get("class_name", "")
    var content = params.get("content", "")
    var signals_data = params.get("signals", [])
    var methods_data = params.get("methods", [])

    var code = ""

    if content != "" and signals_data.size() == 0 and methods_data.size() == 0 and class_name_str == "":
        code = content
    else:
        if class_name_str != "":
            code += "class_name %s\n" % class_name_str
        if extends_class != "":
            code += "extends %s\n\n" % extends_class

        if signals_data.size() > 0:
            for s in signals_data:
                if typeof(s) == TYPE_STRING:
                    var sig_str = String(s)
                    if not sig_str.begins_with("signal"):
                        sig_str = "signal " + sig_str
                    code += sig_str + "\n"
                elif typeof(s) == TYPE_DICTIONARY:
                    var s_name = s.get("name", "")
                    var s_args = s.get("args", s.get("params", []))
                    if s_name != "":
                        if s_args.size() > 0:
                            var arg_strs = []
                            for a in s_args:
                                arg_strs.append(String(a))
                            code += "signal %s(%s)\n" % [s_name, ", ".join(arg_strs)]
                        else:
                            code += "signal %s\n" % s_name
            code += "\n"

        if methods_data.size() > 0:
            for m in methods_data:
                if typeof(m) == TYPE_DICTIONARY:
                    var m_name = m.get("name", "")
                    var m_args = m.get("args", m.get("params", []))
                    var m_ret = m.get("return_type", "")
                    var m_body = m.get("content", m.get("body", "pass"))
                    if m_name != "":
                        var arg_str = ""
                        if m_args.size() > 0:
                            var arg_strs = []
                            for a in m_args:
                                arg_strs.append(String(a))
                            arg_str = ", ".join(arg_strs)
                        var ret_str = (" -> %s" % m_ret) if m_ret != "" else ""
                        code += "func %s(%s)%s:\n" % [m_name, arg_str, ret_str]
                        var body_lines = String(m_body).split("\n")
                        for bl in body_lines:
                            code += "\t%s\n" % bl
                        code += "\n"

        if content != "":
            code += content + "\n"
        elif methods_data.size() == 0:
            code += "func _ready():\n\tpass\n"

    var f = FileAccess.open(script_path, FileAccess.WRITE)
    if not f:
        return {"status": "error", "error": "Failed to open script path for writing: " + script_path}
    f.store_string(code)
    f.close()

    if editor_interface:
        editor_interface.get_resource_filesystem().scan()

    return {"status": "ok", "result": {"script_path": script_path, "code": code}}

func attach_script_in_editor(params: Dictionary) -> Dictionary:
    var script_path = params.get("script_path", "")
    var node_path = params.get("node_path", ".")
    if script_path == "":
        return {"status": "error", "error": "Missing script_path"}
    if not FileAccess.file_exists(script_path):
        return {"status": "error", "error": "Script file not found: " + script_path}

    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Target node not found: " + node_path}

    var scr = ResourceLoader.load(script_path) as Script
    if not scr:
        return {"status": "error", "error": "Failed to load script resource at: " + script_path}

    if undo_redo_manager:
        var old_scr = target.get_script()
        undo_redo_manager.create_action("Attach Script to " + target.name)
        undo_redo_manager.add_do_method(target, "set_script", scr)
        undo_redo_manager.add_undo_method(target, "set_script", old_scr)
        undo_redo_manager.commit_action()
    else:
        target.set_script(scr)

    return {"status": "ok", "result": {"node_path": String(target.get_path()), "script_path": script_path}}

func edit_script_in_editor(params: Dictionary) -> Dictionary:
    var script_path = params.get("script_path", "")
    var code = params.get("code", "")
    if script_path == "":
        return {"status": "error", "error": "Missing script_path"}

    var has_line_start = params.has("line_start")
    var has_line_end = params.has("line_end")

    if has_line_start or has_line_end:
        if not FileAccess.file_exists(script_path):
            return {"status": "error", "error": "Script file not found: " + script_path}
        
        var existing_file = FileAccess.open(script_path, FileAccess.READ)
        var existing_text = existing_file.get_as_text()
        existing_file.close()

        var lines = Array(existing_text.split("\n"))
        var l_start = int(params.get("line_start", 1))
        var l_end = int(params.get("line_end", l_start))

        l_start = clamp(l_start, 1, max(1, lines.size()))
        l_end = clamp(l_end, l_start, max(l_start, lines.size()))

        var new_lines = Array(code.split("\n"))
        
        var head = lines.slice(0, l_start - 1)
        var tail = lines.slice(l_end)
        var final_lines = []
        final_lines.append_array(head)
        final_lines.append_array(new_lines)
        final_lines.append_array(tail)

        code = "\n".join(final_lines)

    var file = FileAccess.open(script_path, FileAccess.WRITE)
    if not file:
        return {"status": "error", "error": "Cannot open file for writing: " + script_path}

    file.store_string(code)
    file.close()

    if editor_interface:
        editor_interface.get_resource_filesystem().scan()

    return {"status": "ok", "result": {"script_path": script_path, "modified": true}}

func validate_script_in_editor(params: Dictionary) -> Dictionary:
    var script_path = params.get("script_path", "")
    if script_path == "":
        return {"status": "error", "error": "Missing script_path"}
    if not FileAccess.file_exists(script_path):
        return {"status": "error", "error": "Script file not found: " + script_path}

    var scr = ResourceLoader.load(script_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as Script
    if scr and scr.can_instantiate():
        return {"status": "ok", "result": {"valid": true, "script_path": script_path, "can_instantiate": true}}
    return {"status": "error", "error": "Script validation failed"}

func analyze_gdscript_ast_in_editor(params: Dictionary) -> Dictionary:
    return analyze_gdscript_ast(params)

func find_script_references_in_editor(params: Dictionary) -> Dictionary:
    return find_script_references(params)

func analyze_gdscript_ast(params: Dictionary) -> Dictionary:
    var script_path = String(params.get("script_path", params.get("path", params.get("file_path", "")))).strip_edges()
    var code = String(params.get("code", params.get("content", "")))

    if script_path != "" and code == "":
        if not FileAccess.file_exists(script_path):
            return {"status": "error", "error": "Script file not found: " + script_path}
        code = FileAccess.get_file_as_string(script_path)

    if code == "":
        return {"status": "error", "error": "No script_path or code provided for AST analysis"}

    var ast = _parse_gdscript_ast_text(code)

    if script_path != "" and FileAccess.file_exists(script_path):
        var scr = ResourceLoader.load(script_path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as Script
        if scr:
            if String(ast.get("class_name", "")) == "" and scr.get_global_name() != "":
                ast["class_name"] = scr.get_global_name()
            if String(ast.get("extends", "")) == "" and scr.get_instance_base_type() != "":
                ast["extends"] = scr.get_instance_base_type()

    return {"status": "ok", "result": ast}

func _parse_gdscript_ast_text(code: String) -> Dictionary:
    var ast = {
        "class_name": "",
        "extends": "",
        "exported_variables": [],
        "function_signatures": [],
        "signal_definitions": [],
        "inner_classes": []
    }

    var lines = code.split("\n")
    var total_lines = lines.size()
    var idx = 0

    var re_class_name = RegEx.create_from_string("^\\s*class_name\\s+([A-Za-z0-9_]+)")
    var re_extends = RegEx.create_from_string("^\\s*extends\\s+([A-Za-z0-9_]+|\"[^\"]+\"|'[^']+')")
    var re_signal = RegEx.create_from_string("^\\s*signal\\s+([A-Za-z0-9_]+)(?:\\s*\\(([^)]*)\\))?")
    var re_export_var = RegEx.create_from_string("^\\s*(@export[a-zA-Z0-9_]*(?:\\([^)]*\\))?)\\s*(?:@\\w+\\s*)*var\\s+([A-Za-z0-9_]+)(?:\\s*:\\s*([A-Za-z0-9_\\[\\]\\.]+))?(?:\\s*=\\s*(.*))?")
    var re_var = RegEx.create_from_string("^\\s*var\\s+([A-Za-z0-9_]+)(?:\\s*:\\s*([A-Za-z0-9_\\[\\]\\.]+))?(?:\\s*=\\s*(.*))?")
    var re_export_anno = RegEx.create_from_string("^\\s*(@export[a-zA-Z0-9_]*(?:\\([^)]*\\))?)")
    var re_func = RegEx.create_from_string("^\\s*(static\\s+)?func\\s+([A-Za-z0-9_]+)\\s*\\(([^)]*)\\)(?:\\s*->\\s*([A-Za-z0-9_\\[\\]\\.]+))?:")
    var re_inner_class = RegEx.create_from_string("^\\s*class\\s+([A-Za-z0-9_]+)(?:\\s+extends\\s+([A-Za-z0-9_]+|\"[^\"]+\"|'[^']+'))?:")

    var pending_export_anno = ""

    while idx < total_lines:
        var line_num = idx + 1
        var line = lines[idx]

        var clean_line = _strip_gdscript_comment(line)
        var trimmed = clean_line.strip_edges()

        if trimmed == "":
            idx += 1
            continue

        # 1. class_name
        var m_class = re_class_name.search(clean_line)
        if m_class:
            ast["class_name"] = m_class.get_string(1)
            pending_export_anno = ""
            idx += 1
            continue

        # 2. extends
        var m_ext = re_extends.search(clean_line)
        if m_ext:
            ast["extends"] = m_ext.get_string(1).trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
            pending_export_anno = ""
            idx += 1
            continue

        # 3. signal
        var m_sig = re_signal.search(clean_line)
        if m_sig:
            var sig_name = m_sig.get_string(1)
            var args_raw = m_sig.get_string(2)
            var sig_args = _parse_gdscript_args(args_raw)
            ast["signal_definitions"].append({
                "name": sig_name,
                "args": sig_args
            })
            pending_export_anno = ""
            idx += 1
            continue

        # 4. inner class declaration
        var m_ic = re_inner_class.search(clean_line)
        if m_ic:
            var ic_name = m_ic.get_string(1)
            var ic_extends = m_ic.get_string(2).trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
            var ic_indent = _get_indent_level(line)

            var ic_lines: Array = []
            idx += 1
            while idx < total_lines:
                var next_line = lines[idx]
                var next_clean = _strip_gdscript_comment(next_line).strip_edges()
                if next_clean != "":
                    var next_indent = _get_indent_level(next_line)
                    if next_indent <= ic_indent:
                        break
                ic_lines.append(next_line)
                idx += 1

            var ic_code = ""
            for icl in ic_lines:
                ic_code += icl + "\n"

            var ic_ast = _parse_gdscript_ast_text(ic_code)
            ic_ast["name"] = ic_name
            if ic_extends != "":
                ic_ast["extends"] = ic_extends
            ast["inner_classes"].append(ic_ast)
            pending_export_anno = ""
            continue

        # 5. func signature
        var full_func_line = clean_line
        var orig_func_idx = idx
        if "func " in clean_line and not (":" in clean_line):
            var peek_idx = idx + 1
            while peek_idx < total_lines and not (":" in full_func_line):
                full_func_line += " " + _strip_gdscript_comment(lines[peek_idx]).strip_edges()
                peek_idx += 1

        var m_func = re_func.search(full_func_line)
        if m_func:
            var is_static = m_func.get_string(1) != ""
            var func_name = m_func.get_string(2)
            var args_raw = m_func.get_string(3)
            var ret_type = m_func.get_string(4)
            if ret_type == "": ret_type = "void"
            var func_args = _parse_gdscript_args(args_raw)
            ast["function_signatures"].append({
                "name": func_name,
                "is_static": is_static,
                "args": func_args,
                "return_type": ret_type,
                "line": line_num
            })
            pending_export_anno = ""
            if "func " in clean_line and not (":" in clean_line):
                idx = orig_func_idx + full_func_line.count("\n") + 1
            else:
                idx += 1
            continue

        # 6. @export variable
        var m_exp_var = re_export_var.search(clean_line)
        if m_exp_var:
            var anno = m_exp_var.get_string(1)
            var var_name = m_exp_var.get_string(2)
            var var_type = m_exp_var.get_string(3)
            var var_def = m_exp_var.get_string(4).strip_edges()
            ast["exported_variables"].append({
                "name": var_name,
                "type": var_type if var_type != "" else "Variant",
                "default_value": var_def if var_def != "" else null,
                "annotation": anno
            })
            pending_export_anno = ""
            idx += 1
            continue

        var m_anno = re_export_anno.search(clean_line)
        if m_anno and not ("var " in clean_line):
            pending_export_anno = m_anno.get_string(1)
            idx += 1
            continue

        if pending_export_anno != "" and "var " in clean_line:
            var m_v = re_var.search(clean_line)
            if m_v:
                var var_name = m_v.get_string(1)
                var var_type = m_v.get_string(2)
                var var_def = m_v.get_string(3).strip_edges()
                ast["exported_variables"].append({
                    "name": var_name,
                    "type": var_type if var_type != "" else "Variant",
                    "default_value": var_def if var_def != "" else null,
                    "annotation": pending_export_anno
                })
            pending_export_anno = ""
            idx += 1
            continue

        pending_export_anno = ""
        idx += 1

    return ast

func _strip_gdscript_comment(line: String) -> String:
    var in_quotes = false
    var quote_char = ""
    var i = 0
    while i < line.length():
        var c = line[i]
        if not in_quotes:
            if c == '"' or c == "'":
                in_quotes = true
                quote_char = c
            elif c == '#':
                return line.substr(0, i)
        else:
            if c == quote_char and (i == 0 or line[i - 1] != '\\'):
                in_quotes = false
        i += 1
    return line

func _get_indent_level(line: String) -> int:
    var indent = 0
    for i in range(line.length()):
        var c = line[i]
        if c == '\t':
            indent += 4
        elif c == ' ':
            indent += 1
        else:
            break
    return indent

func _parse_gdscript_args(args_raw: String) -> Array:
    var result: Array = []
    if args_raw.strip_edges() == "":
        return result

    var raw_parts: Array = []
    var current = ""
    var depth = 0
    var in_quotes = false
    var quote_c = ""

    for i in range(args_raw.length()):
        var c = args_raw[i]
        if not in_quotes:
            if c == '"' or c == "'":
                in_quotes = true
                quote_c = c
                current += c
            elif c in ['(', '[', '{']:
                depth += 1
                current += c
            elif c in [')', ']', '}']:
                depth -= 1
                current += c
            elif c == ',' and depth == 0:
                raw_parts.append(current.strip_edges())
                current = ""
            else:
                current += c
        else:
            current += c
            if c == quote_c and (i == 0 or args_raw[i - 1] != '\\'):
                in_quotes = false

    if current.strip_edges() != "":
        raw_parts.append(current.strip_edges())

    for part in raw_parts:
        if part == "": continue
        var arg_name = part
        var arg_type = ""
        var default_val = null

        if "=" in part:
            var eq_idx = part.find("=")
            default_val = part.substr(eq_idx + 1).strip_edges()
            part = part.substr(0, eq_idx).strip_edges()

        if ":" in part:
            var colon_idx = part.find(":")
            arg_type = part.substr(colon_idx + 1).strip_edges()
            arg_name = part.substr(0, colon_idx).strip_edges()
        else:
            arg_name = part.strip_edges()

        result.append({
            "name": arg_name,
            "type": arg_type if arg_type != "" else "Variant",
            "default_value": default_val
        })

    return result

func find_script_references(params: Dictionary) -> Dictionary:
    var target_path = String(params.get("target_path", params.get("target", params.get("script_path", "")))).strip_edges()
    if target_path == "":
        return {"status": "error", "error": "Missing target_path parameter"}

    var project_dir = String(params.get("project_path", params.get("search_dir", "res://")))
    if project_dir == "": project_dir = "res://"

    var search_tokens: Array = []
    
    var res_path = target_path
    if not res_path.begins_with("res://"):
        res_path = "res://" + target_path.trim_prefix("./").trim_prefix("/")
    
    var rel_path = res_path.trim_prefix("res://")
    var file_name = target_path.get_file()

    search_tokens.append(res_path)
    if rel_path != res_path and not (rel_path in search_tokens):
        search_tokens.append(rel_path)

    if FileAccess.file_exists(res_path) and res_path.ends_with(".gd"):
        var code = FileAccess.get_file_as_string(res_path)
        var re_cn = RegEx.create_from_string("^\\s*class_name\\s+([A-Za-z0-9_]+)")
        var m = re_cn.search(code)
        if m:
            var cn = m.get_string(1)
            if not (cn in search_tokens):
                search_tokens.append(cn)

    if FileAccess.file_exists(res_path):
        if ResourceLoader.has_method("get_resource_uid"):
            var uid_val = ResourceLoader.get_resource_uid(res_path)
            if uid_val > 0 and ResourceUID.has_method("id_to_text"):
                var uid_text = ResourceUID.id_to_text(uid_val)
                if uid_text != "" and not (uid_text in search_tokens):
                    search_tokens.append(uid_text)

    var files_to_scan: Array = []
    _collect_script_ref_files_recursive(project_dir, files_to_scan)

    var references: Array = []

    for file_path in files_to_scan:
        if file_path == res_path:
            continue

        var fa = FileAccess.open(file_path, FileAccess.READ)
        if not fa:
            continue

        var file_ext = file_path.get_extension().to_lower()
        var file_type = "script" if file_ext == "gd" else ("scene" if file_ext == "tscn" else ("resource" if file_ext == "tres" else "other"))

        var line_num = 0
        while not fa.eof_reached():
            var line = fa.get_line()
            line_num += 1
            
            var matched_token = ""
            for token in search_tokens:
                if token in line:
                    matched_token = token
                    break
            
            if matched_token != "":
                var ref_type = "occurrence"
                if "[ext_resource" in line:
                    ref_type = "ext_resource"
                elif "preload(" in line:
                    ref_type = "preload"
                elif "load(" in line:
                    ref_type = "load"
                elif "extends " in line:
                    ref_type = "extends"
                elif "instance=" in line:
                    ref_type = "instantiate"
                elif "script = " in line:
                    ref_type = "script_attachment"

                references.append({
                    "file_path": file_path,
                    "file_type": file_type,
                    "line_number": line_num,
                    "line_content": line.strip_edges(),
                    "reference_type": ref_type,
                    "matched_token": matched_token
                })

    return {
        "status": "ok",
        "result": {
            "target_path": res_path,
            "search_tokens": search_tokens,
            "total_references": references.size(),
            "references": references
        }
    }

func _collect_script_ref_files_recursive(dir_path: String, out_files: Array):
    var dir = DirAccess.open(dir_path)
    if not dir:
        return
    dir.list_dir_begin()
    var file_name = dir.get_next()
    while file_name != "":
        if not file_name.begins_with("."):
            var full_path = dir_path.path_join(file_name)
            if dir.current_is_dir():
                _collect_script_ref_files_recursive(full_path, out_files)
            else:
                var ext = file_name.get_extension().to_lower()
                if ext in ["tscn", "tres", "gd"]:
                    out_files.append(full_path)
        file_name = dir.get_next()
    dir.list_dir_end()

func parse_connect_flags(flags_val) -> int:
    if typeof(flags_val) == TYPE_INT or typeof(flags_val) == TYPE_FLOAT:
        return int(flags_val)
    var flags = 0
    if typeof(flags_val) == TYPE_ARRAY:
        for f in flags_val:
            var s = String(f).to_lower()
            if "deferred" in s: flags |= Object.CONNECT_DEFERRED
            if "persist" in s: flags |= Object.CONNECT_PERSIST
            if "one" in s or "shot" in s: flags |= Object.CONNECT_ONE_SHOT
            if "ref" in s: flags |= Object.CONNECT_REFERENCE_COUNTED
    elif typeof(flags_val) == TYPE_STRING:
        var s = String(flags_val).to_lower()
        if "deferred" in s: flags |= Object.CONNECT_DEFERRED
        if "persist" in s: flags |= Object.CONNECT_PERSIST
        if "one" in s or "shot" in s: flags |= Object.CONNECT_ONE_SHOT
        if "ref" in s: flags |= Object.CONNECT_REFERENCE_COUNTED
    if flags == 0:
        flags = Object.CONNECT_PERSIST
    return flags

func connect_signal_in_editor(params: Dictionary) -> Dictionary:
    var signal_name = params.get("signal_name", "")
    var source_path = params.get("source_node_path", params.get("source_path", ""))
    var target_path = params.get("target_node_path", params.get("target_path", ""))
    var target_method = params.get("target_method", "")
    var binds = params.get("binds", [])
    var flags_val = params.get("flags", 2)

    if signal_name == "" or source_path == "" or target_path == "" or target_method == "":
        return {"status": "error", "error": "Missing required signal connection parameters"}

    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var source_node = root if (source_path == "." or source_path == "") else root.get_node_or_null(source_path)
    var target_node = root if (target_path == "." or target_path == "") else root.get_node_or_null(target_path)

    if not source_node or not target_node:
        return {"status": "error", "error": "Source or target node not found in open scene"}

    if not source_node.has_signal(signal_name):
        return {"status": "error", "error": "Node '%s' does not have signal '%s'" % [source_path, signal_name]}

    var flags = parse_connect_flags(flags_val)
    var callable = Callable(target_node, target_method)
    if binds.size() > 0:
        var parsed_binds = []
        for b in binds:
            parsed_binds.append(parse_variant(b))
        callable = callable.bindv(parsed_binds)

    if undo_redo_manager:
        if source_node.is_connected(signal_name, callable):
            source_node.disconnect(signal_name, callable)
        undo_redo_manager.create_action("Connect Signal " + signal_name)
        undo_redo_manager.add_do_method(source_node, "connect", signal_name, callable, flags)
        undo_redo_manager.add_undo_method(source_node, "disconnect", signal_name, callable)
        undo_redo_manager.commit_action()
    else:
        if source_node.is_connected(signal_name, callable):
            source_node.disconnect(signal_name, callable)
        source_node.connect(signal_name, callable, flags)

    return {
        "status": "ok",
        "result": {
            "signal_name": signal_name,
            "source_node_path": String(source_node.get_path()),
            "target_node_path": String(target_node.get_path()),
            "target_method": target_method,
            "flags": flags
        }
    }

func disconnect_signal_in_editor(params: Dictionary) -> Dictionary:
    var signal_name = params.get("signal_name", "")
    var source_path = params.get("source_node_path", params.get("source_path", ""))
    var target_path = params.get("target_node_path", params.get("target_path", ""))
    var target_method = params.get("target_method", "")

    if signal_name == "" or source_path == "" or target_path == "" or target_method == "":
        return {"status": "error", "error": "Missing required signal disconnection parameters"}

    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var source_node = root if (source_path == "." or source_path == "") else root.get_node_or_null(source_path)
    var target_node = root if (target_path == "." or target_path == "") else root.get_node_or_null(target_path)

    if not source_node or not target_node:
        return {"status": "error", "error": "Source or target node not found in open scene"}

    var callable = Callable(target_node, target_method)
    if not source_node.is_connected(signal_name, callable):
        return {"status": "error", "error": "Signal '%s' is not connected to '%s::%s'" % [signal_name, target_path, target_method]}

    if undo_redo_manager:
        undo_redo_manager.create_action("Disconnect Signal " + signal_name)
        undo_redo_manager.add_do_method(source_node, "disconnect", signal_name, callable)
        undo_redo_manager.add_undo_method(source_node, "connect", signal_name, callable, Object.CONNECT_PERSIST)
        undo_redo_manager.commit_action()
    else:
        source_node.disconnect(signal_name, callable)

    return {
        "status": "ok",
        "result": {
            "signal_name": signal_name,
            "source_node_path": String(source_node.get_path()),
            "target_node_path": String(target_node.get_path()),
            "target_method": target_method,
            "disconnected": true
        }
    }

func list_signals_in_editor(params: Dictionary) -> Dictionary:
    var node_path = params.get("node_path", ".")
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var target_node = root if (node_path == "." or node_path == "" or (root and node_path == root.name)) else root.get_node_or_null(node_path)
    if not target_node:
        return {"status": "error", "error": "Node not found at path: " + node_path}

    var signals_list = []
    for sig in target_node.get_signal_list():
        var sig_name = sig.get("name", "")
        var sig_args = sig.get("args", [])
        var conn_list = []

        for c in target_node.get_signal_connection_list(sig_name):
            var callable = c.get("callable", null)
            var target_obj = c.get("target", null)
            var c_target_path = ""
            var c_method = ""
            if target_obj is Node:
                c_target_path = String((target_obj as Node).get_path())
            if callable is Callable:
                c_method = (callable as Callable).get_method()

            conn_list.append({
                "target_node_path": c_target_path,
                "target_method": c_method,
                "flags": c.get("flags", 0)
            })

        signals_list.append({
            "name": sig_name,
            "args": sig_args,
            "connections": conn_list
        })

    return {"status": "ok", "result": {"node_path": String(target_node.get_path()), "signals": signals_list}}

func configure_audio_bus_in_editor(params: Dictionary) -> Dictionary:
    var bus_name = params.get("bus_name", "")
    if bus_name == "":
        return {"status": "error", "error": "Missing bus_name"}

    var bus_idx = AudioServer.get_bus_index(bus_name)
    if bus_idx == -1:
        AudioServer.add_bus()
        bus_idx = AudioServer.get_bus_count() - 1
        AudioServer.set_bus_name(bus_idx, bus_name)

    if params.has("volume_db"):
        AudioServer.set_bus_volume_db(bus_idx, float(params["volume_db"]))

    if params.has("send_bus"):
        var send_name = String(params["send_bus"])
        if send_name != "":
            AudioServer.set_bus_send(bus_idx, send_name)

    var effect_added = ""
    var add_effect_val = params.get("add_effect", null)
    var effect_type = params.get("effect_type", "")

    var effect_class_name = ""
    if typeof(add_effect_val) == TYPE_STRING and String(add_effect_val) != "" and String(add_effect_val) != "true" and String(add_effect_val) != "false":
        effect_class_name = String(add_effect_val)
    elif effect_type != "":
        effect_class_name = effect_type

    if effect_class_name != "":
        if not effect_class_name.begins_with("AudioEffect"):
            effect_class_name = "AudioEffect" + effect_class_name
        if ClassDB.class_exists(effect_class_name):
            var eff_inst = ClassDB.instantiate(effect_class_name) as AudioEffect
            if eff_inst:
                AudioServer.add_bus_effect(bus_idx, eff_inst)
                effect_added = effect_class_name

    return {
        "status": "ok",
        "result": {
            "bus_name": bus_name,
            "bus_index": bus_idx,
            "volume_db": AudioServer.get_bus_volume_db(bus_idx),
            "send_bus": AudioServer.get_bus_send(bus_idx),
            "effect_added": effect_added
        }
    }

func create_audio_stream_player_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var parent_path = params.get("parent_path", ".")
    var node_name = params.get("node_name", "")
    var stream_path = params.get("stream_path", "")
    var bus_name = params.get("bus_name", "Master")
    var autoplay = params.get("autoplay", false)
    var volume_db = float(params.get("volume_db", 0.0))
    var pitch_scale = float(params.get("pitch_scale", 1.0))
    var is_3d = params.get("is_3d", false)
    var is_2d = params.get("is_2d", false)

    var parent = root if (parent_path == "." or parent_path == "") else root.get_node_or_null(parent_path)
    if not parent:
        return {"status": "error", "error": "Parent node not found: " + parent_path}

    var player_node: Node = null
    var default_name = "AudioStreamPlayer"

    if is_3d:
        player_node = AudioStreamPlayer3D.new()
        default_name = "AudioStreamPlayer3D"
    elif is_2d:
        player_node = AudioStreamPlayer2D.new()
        default_name = "AudioStreamPlayer2D"
    else:
        player_node = AudioStreamPlayer.new()
        default_name = "AudioStreamPlayer"

    player_node.name = node_name if node_name != "" else default_name

    if stream_path != "" and FileAccess.file_exists(stream_path):
        var stream_res = ResourceLoader.load(stream_path) as AudioStream
        if stream_res:
            player_node.set("stream", stream_res)

    player_node.set("bus", bus_name)
    player_node.set("autoplay", autoplay)
    player_node.set("volume_db", volume_db)
    player_node.set("pitch_scale", pitch_scale)

    if undo_redo_manager:
        undo_redo_manager.create_action("Add " + player_node.name)
        undo_redo_manager.add_do_method(parent, "add_child", player_node)
        undo_redo_manager.add_do_method(player_node, "set_owner", root)
        undo_redo_manager.add_do_reference(player_node)
        undo_redo_manager.add_undo_method(parent, "remove_child", player_node)
        undo_redo_manager.commit_action()
    else:
        parent.add_child(player_node)
        player_node.owner = root

    return {
        "status": "ok",
        "result": {
            "node_name": player_node.name,
            "node_path": String(player_node.get_path()),
            "bus": bus_name,
            "stream_path": stream_path
        }
    }

func simulate_input_event(params: Dictionary) -> Dictionary:
    var event_type = params.get("event_type", params.get("type", "action"))
    var pressed = params.get("pressed", true)

    match String(event_type).to_lower():
        "action":
            var action_name = params.get("action", "")
            if action_name == "":
                return {"status": "error", "error": "Missing action name for action event"}
            var ev = InputEventAction.new()
            ev.action = action_name
            ev.pressed = pressed
            Input.parse_input_event(ev)
            return {"status": "ok", "result": {"event_type": "action", "action": action_name, "pressed": pressed}}

        "key":
            var kc_raw = params.get("key_code", params.get("keycode", 0))
            var kc = parse_key_code(kc_raw)
            if kc == KEY_NONE:
                return {"status": "error", "error": "Invalid key_code: " + String(kc_raw)}
            var ev = InputEventKey.new()
            ev.keycode = kc
            ev.physical_keycode = kc
            ev.pressed = pressed
            Input.parse_input_event(ev)
            return {"status": "ok", "result": {"event_type": "key", "key_code": kc, "pressed": pressed}}

        "mouse_button":
            var button_idx = int(params.get("mouse_button_index", params.get("button_index", 1)))
            var pos = parse_vector2(params.get("position", Vector2.ZERO))
            var ev = InputEventMouseButton.new()
            ev.button_index = button_idx as MouseButton
            ev.pressed = pressed
            ev.position = pos
            ev.global_position = pos
            Input.parse_input_event(ev)
            return {"status": "ok", "result": {"event_type": "mouse_button", "button_index": button_idx, "pressed": pressed, "position": {"x": pos.x, "y": pos.y}}}

        "mouse_motion":
            var pos = parse_vector2(params.get("position", Vector2.ZERO))
            var rel = parse_vector2(params.get("relative_motion", params.get("relative", Vector2.ZERO)))
            var ev = InputEventMouseMotion.new()
            ev.position = pos
            ev.global_position = pos
            ev.relative = rel
            Input.parse_input_event(ev)
            return {"status": "ok", "result": {"event_type": "mouse_motion", "position": {"x": pos.x, "y": pos.y}, "relative_motion": {"x": rel.x, "y": rel.y}}}

        _:
            return {"status": "error", "error": "Unsupported event_type: " + String(event_type)}

func replay_input_sequence(params: Dictionary) -> Dictionary:
    var sequence = params.get("sequence", [])
    if typeof(sequence) != TYPE_ARRAY:
        return {"status": "error", "error": "Parameter 'sequence' must be an Array"}

    var log_messages: Array = []
    var steps_executed: int = 0
    var last_timestamp: float = -1.0

    for i in range(sequence.size()):
        var step = sequence[i]
        if typeof(step) != TYPE_DICTIONARY:
            continue

        var step_num = i + 1
        var timestamp = float(step.get("timestamp", -1.0))
        if timestamp >= 0.0:
            if last_timestamp >= 0.0 and timestamp > last_timestamp:
                var delay_sec = timestamp - last_timestamp
                OS.delay_msec(int(delay_sec * 1000.0))
                log_messages.append("Step %d: Timestamp delay %.3fs" % [step_num, delay_sec])
            last_timestamp = timestamp

        var event_type = String(step.get("type", step.get("event_type", "")))
        if event_type == "":
            if step.has("action"):
                event_type = "action"
            elif step.has("key_code") or step.has("keycode"):
                event_type = "key"
            elif step.has("mouse_button_index") or step.has("button_index"):
                event_type = "mouse_button"
            else:
                event_type = "action"

        event_type = event_type.to_lower()
        var duration = float(step.get("duration", step.get("delay", 0.0)))
        var pressed = step.get("pressed", true)

        if event_type == "delay" or event_type == "wait" or event_type == "sleep":
            var delay_time = duration if duration > 0.0 else float(step.get("time", step.get("seconds", 0.0)))
            if delay_time > 0.0:
                OS.delay_msec(int(delay_time * 1000.0))
                log_messages.append("Step %d: Delayed for %.3fs" % [step_num, delay_time])
            steps_executed += 1
            continue

        var sim_step = step.duplicate()
        sim_step["event_type"] = event_type

        var sim_res = simulate_input_event(sim_step)
        if sim_res.get("status") == "error":
            log_messages.append("Step %d: Error - %s" % [step_num, sim_res.get("error", "Unknown error")])
        else:
            var desc = "Simulated %s" % event_type
            if event_type == "action":
                desc += " '%s' (pressed=%s)" % [step.get("action", ""), String(pressed)]
            elif event_type == "key":
                desc += " key_code '%s' (pressed=%s)" % [String(step.get("key_code", step.get("keycode", ""))), String(pressed)]
            elif event_type == "mouse_button":
                desc += " button %s (pressed=%s)" % [String(step.get("mouse_button_index", step.get("button_index", 1))), String(pressed)]
            elif event_type == "mouse_motion":
                desc += " motion"

            log_messages.append("Step %d: %s" % [step_num, desc])

            if duration > 0.0:
                OS.delay_msec(int(duration * 1000.0))
                if pressed:
                    var release_step = sim_step.duplicate()
                    release_step["pressed"] = false
                    simulate_input_event(release_step)
                    log_messages.append("Step %d: Released after %.3fs duration" % [step_num, duration])
                else:
                    log_messages.append("Step %d: Held duration %.3fs" % [step_num, duration])

        steps_executed += 1

    var take_ss = params.get("take_screenshot", true)
    var screenshot_status = {}
    if take_ss:
        var ss_res = take_viewport_screenshot(params)
        if ss_res.get("status") == "ok":
            screenshot_status = ss_res.get("result", {})
            screenshot_status["captured"] = true
        else:
            screenshot_status = {"captured": false, "error": ss_res.get("error", "Failed to take screenshot")}
    else:
        screenshot_status = {"captured": false, "reason": "Screenshot disabled by params"}

    return {
        "status": "ok",
        "result": {
            "log": log_messages,
            "steps_executed": steps_executed,
            "screenshot_status": screenshot_status
        }
    }

func take_viewport_screenshot(params: Dictionary = {}) -> Dictionary:
    if not editor_interface:
        return {"status": "error", "error": "EditorInterface not available"}

    var vp = editor_interface.get_viewport()
    if not vp:
        return {"status": "error", "error": "Viewport unavailable"}

    var tex = vp.get_texture()
    if not tex:
        return {"status": "error", "error": "Viewport texture unavailable"}

    var img = tex.get_image()
    if not img or img.is_empty():
        return {"status": "error", "error": "Failed to retrieve image from viewport"}

    return process_and_encode_image(img, params)

func create_shader_material_in_editor(params: Dictionary) -> Dictionary:
    var shader_code = params.get("shader_code", params.get("code", ""))
    var shader_type = params.get("shader_type", params.get("type", "canvas_item"))
    var save_path = params.get("save_path", params.get("output_path", ""))
    var shader_save_path = params.get("shader_path", "")
    var node_path = params.get("node_path", "")
    var shader_params = params.get("shader_parameters", params.get("uniforms", {}))

    if shader_code == "":
        shader_code = "shader_type %s;\n\nvoid fragment() {\n\t// Default fragment shader\n}\n" % shader_type
    elif not shader_code.strip_edges().begins_with("shader_type"):
        shader_code = "shader_type %s;\n\n" % shader_type + shader_code

    var shader = Shader.new()
    shader.code = shader_code

    if shader_save_path != "":
        var s_err = ResourceSaver.save(shader, shader_save_path)
        if s_err != OK:
            return {"status": "error", "error": "Failed to save shader to '%s': %d" % [shader_save_path, s_err]}

    var mat = ShaderMaterial.new()
    mat.shader = shader

    for u_name in shader_params:
        var val = resolve_shader_param_value(shader_params[u_name])
        mat.set_shader_parameter(u_name, val)

    if save_path != "":
        var m_err = ResourceSaver.save(mat, save_path)
        if m_err != OK:
            return {"status": "error", "error": "Failed to save material to '%s': %d" % [save_path, m_err]}

    if editor_interface:
        editor_interface.get_resource_filesystem().scan()

    if node_path != "":
        var root = editor_interface.get_edited_scene_root() if editor_interface else null
        if root:
            var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
            if target:
                var prop_name = "material"
                if target is GeometryInstance3D:
                    prop_name = "material_override"

                if undo_redo_manager:
                    undo_redo_manager.create_action("Attach ShaderMaterial to " + target.name)
                    undo_redo_manager.add_do_property(target, prop_name, mat)
                    undo_redo_manager.add_undo_property(target, prop_name, target.get(prop_name))
                    undo_redo_manager.commit_action()
                else:
                    target.set(prop_name, mat)
            else:
                return {"status": "error", "error": "Target node not found in edited scene: " + node_path}

    return {
        "status": "ok",
        "result": {
            "shader_type": shader_type,
            "save_path": save_path,
            "shader_save_path": shader_save_path,
            "attached_to": node_path
        }
    }

func set_shader_parameter_in_editor(params: Dictionary) -> Dictionary:
    var node_path = params.get("node_path", "")
    var material_path = params.get("material_path", "")
    var param_name = params.get("param_name", params.get("parameter_name", params.get("uniform_name", "")))
    var param_value = params.get("value", params.get("param_value", params.get("parameter_value", null)))
    var bulk_params = params.get("parameters", params.get("uniforms", {}))
    var surface_index = int(params.get("surface_index", -1))

    var to_set = {}
    if param_name != "":
        to_set[param_name] = param_value
    for k in bulk_params:
        to_set[k] = bulk_params[k]

    if to_set.is_empty():
        return {"status": "error", "error": "No parameter name or parameters dictionary provided"}

    var mat: ShaderMaterial = null

    if material_path != "":
        if not FileAccess.file_exists(material_path):
            return {"status": "error", "error": "Material resource file not found: " + material_path}
        mat = ResourceLoader.load(material_path) as ShaderMaterial
        if not mat:
            return {"status": "error", "error": "Resource at '%s' is not a ShaderMaterial" % material_path}

        for p_name in to_set:
            var val = resolve_shader_param_value(to_set[p_name])
            mat.set_shader_parameter(p_name, val)

        var err = ResourceSaver.save(mat, material_path)
        if err != OK:
            return {"status": "error", "error": "Failed to save material to '%s': %d" % [material_path, err]}
        
        if editor_interface:
            editor_interface.get_resource_filesystem().scan()

        return {"status": "ok", "result": {"material_path": material_path, "updated_parameters": to_set.keys()}}

    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor and no material_path specified"}

    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Node not found at path: " + node_path}

    mat = get_shader_material_from_node(target, surface_index)
    if not mat:
        return {"status": "error", "error": "No ShaderMaterial found on node: " + node_path}

    for p_name in to_set:
        var val = resolve_shader_param_value(to_set[p_name])
        if undo_redo_manager:
            var old_val = mat.get_shader_parameter(p_name)
            undo_redo_manager.create_action("Set Shader Parameter " + p_name)
            undo_redo_manager.add_do_method(mat, "set_shader_parameter", p_name, val)
            undo_redo_manager.add_undo_method(mat, "set_shader_parameter", p_name, old_val)
            undo_redo_manager.commit_action()
        else:
            mat.set_shader_parameter(p_name, val)

    return {
        "status": "ok",
        "result": {
            "node_path": node_path,
            "updated_parameters": to_set.keys()
        }
    }

func create_visual_shader_in_editor(params: Dictionary) -> Dictionary:
    var shader_mode_str = params.get("shader_type", params.get("mode", "canvas_item"))
    var save_path = params.get("save_path", params.get("output_path", ""))
    var nodes_data = params.get("nodes", [])
    var connections_data = params.get("connections", [])
    var create_material = params.get("create_material", true)
    var material_save_path = params.get("material_save_path", "")
    var node_path = params.get("node_path", "")

    var vs = VisualShader.new()
    vs.mode = get_visual_shader_mode(String(shader_mode_str))

    var created_nodes = []

    for n_data in nodes_data:
        var node_type_name = n_data.get("type", n_data.get("node_type", n_data.get("class_name", "")))
        if node_type_name == "":
            continue
        if not node_type_name.begins_with("VisualShaderNode"):
            node_type_name = "VisualShaderNode" + node_type_name

        if not ClassDB.class_exists(node_type_name):
            push_error("[Godot MCP Server] Invalid VisualShaderNode class: " + node_type_name)
            continue

        var stage_str = n_data.get("stage", n_data.get("shader_stage", "fragment"))
        var stage = get_visual_shader_stage(String(stage_str))

        var node_inst = ClassDB.instantiate(node_type_name) as VisualShaderNode
        if not node_inst:
            continue

        var props = n_data.get("properties", n_data.get("props", {}))
        for p in props:
            node_inst.set(p, resolve_shader_param_value(props[p]))

        var pos_val = n_data.get("position", n_data.get("pos", Vector2.ZERO))
        var pos = parse_variant(pos_val)
        if typeof(pos) != TYPE_VECTOR2:
            pos = Vector2.ZERO

        var explicit_id = int(n_data.get("id", -1))
        var node_id = explicit_id if explicit_id > 0 else vs.get_valid_node_id(stage)

        vs.add_node(stage, node_inst, pos, node_id)
        created_nodes.append({"id": node_id, "class": node_type_name, "stage": stage_str})

    for c_data in connections_data:
        var stage_str = c_data.get("stage", c_data.get("shader_stage", "fragment"))
        var stage = get_visual_shader_stage(String(stage_str))
        var from_node = int(c_data.get("from_node", c_data.get("from_id", 0)))
        var from_port = int(c_data.get("from_port", 0))
        var to_node = int(c_data.get("to_node", c_data.get("to_id", 0)))
        var to_port = int(c_data.get("to_port", 0))

        vs.connect_nodes(stage, from_node, from_port, to_node, to_port)

    if save_path != "":
        var err = ResourceSaver.save(vs, save_path)
        if err != OK:
            return {"status": "error", "error": "Failed to save VisualShader to '%s': %d" % [save_path, err]}

    var mat: ShaderMaterial = null
    if create_material or material_save_path != "" or node_path != "":
        mat = ShaderMaterial.new()
        mat.shader = vs

        if material_save_path != "":
            var m_err = ResourceSaver.save(mat, material_save_path)
            if m_err != OK:
                return {"status": "error", "error": "Failed to save ShaderMaterial to '%s': %d" % [material_save_path, m_err]}

    if editor_interface:
        editor_interface.get_resource_filesystem().scan()

    if node_path != "" and mat:
        var root = editor_interface.get_edited_scene_root() if editor_interface else null
        if root:
            var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
            if target:
                var prop_name = "material"
                if target is GeometryInstance3D:
                    prop_name = "material_override"

                if undo_redo_manager:
                    undo_redo_manager.create_action("Attach VisualShader Material to " + target.name)
                    undo_redo_manager.add_do_property(target, prop_name, mat)
                    undo_redo_manager.add_undo_property(target, prop_name, target.get(prop_name))
                    undo_redo_manager.commit_action()
                else:
                    target.set(prop_name, mat)
            else:
                return {"status": "error", "error": "Target node not found in edited scene: " + node_path}

    return {
        "status": "ok",
        "result": {
            "shader_path": save_path,
            "material_path": material_save_path,
            "nodes_created": created_nodes.size(),
            "attached_to": node_path
        }
    }

func resolve_shader_param_value(val):
    if typeof(val) == TYPE_STRING:
        var s_val = String(val)
        if s_val.begins_with("res://"):
            if ResourceLoader.exists(s_val):
                return ResourceLoader.load(s_val)
    return parse_variant(val)

func get_shader_material_from_node(node: Node, surface_index: int = -1) -> ShaderMaterial:
    if surface_index >= 0 and node is MeshInstance3D:
        var surf_mat = (node as MeshInstance3D).get_surface_override_material(surface_index)
        if surf_mat is ShaderMaterial:
            return surf_mat as ShaderMaterial
    if "material_override" in node and node.material_override is ShaderMaterial:
        return node.material_override as ShaderMaterial
    if "material" in node and node.material is ShaderMaterial:
        return node.material as ShaderMaterial
    return null

func get_visual_shader_mode(mode_str: String) -> int:
    match mode_str.to_lower():
        "spatial", "3d": return VisualShader.MODE_SPATIAL
        "canvas_item", "2d": return VisualShader.MODE_CANVAS_ITEM
        "sky": return VisualShader.MODE_SKY
        "fog": return VisualShader.MODE_FOG
        "particles": return VisualShader.MODE_PARTICLES
        _: return VisualShader.MODE_CANVAS_ITEM

func get_visual_shader_stage(stage_str: String) -> int:
    match stage_str.to_lower():
        "vertex": return VisualShader.TYPE_VERTEX
        "fragment": return VisualShader.TYPE_FRAGMENT
        "light": return VisualShader.TYPE_LIGHT
        "start": return VisualShader.TYPE_START
        "process": return VisualShader.TYPE_PROCESS
        "collide": return VisualShader.TYPE_COLLIDE
        "sky": return VisualShader.TYPE_SKY
        "fog": return VisualShader.TYPE_FOG
        _: return VisualShader.TYPE_FRAGMENT

func set_tilemap_cell_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Target node not found: " + node_path}

    var coords = parse_cell_coords(params)
    var atlas_coords = parse_atlas_coords(params)
    var source_id = int(params.get("source_id", -1))
    var alternative_tile = int(params.get("alternative_tile", 0))
    var layer = int(params.get("layer", 0))

    if target is TileMapLayer:
        if undo_redo_manager:
            var old_source = target.get_cell_source_id(coords)
            var old_atlas = target.get_cell_atlas_coords(coords)
            var old_alt = target.get_cell_alternative_tile(coords)
            undo_redo_manager.create_action("Set TileMapLayer Cell")
            undo_redo_manager.add_do_method(target, "set_cell", coords, source_id, atlas_coords, alternative_tile)
            undo_redo_manager.add_undo_method(target, "set_cell", coords, old_source, old_atlas, old_alt)
            undo_redo_manager.commit_action()
        else:
            target.set_cell(coords, source_id, atlas_coords, alternative_tile)
    elif target is TileMap:
        if undo_redo_manager:
            var old_source = target.get_cell_source_id(layer, coords)
            var old_atlas = target.get_cell_atlas_coords(layer, coords)
            var old_alt = target.get_cell_alternative_tile(layer, coords)
            undo_redo_manager.create_action("Set TileMap Cell")
            undo_redo_manager.add_do_method(target, "set_cell", layer, coords, source_id, atlas_coords, alternative_tile)
            undo_redo_manager.add_undo_method(target, "set_cell", layer, coords, old_source, old_atlas, old_alt)
            undo_redo_manager.commit_action()
        else:
            target.set_cell(layer, coords, source_id, atlas_coords, alternative_tile)
    elif target.has_method("set_cell"):
        target.call("set_cell", coords, source_id, atlas_coords, alternative_tile)
    else:
        return {"status": "error", "error": "Target node '%s' (%s) does not support set_cell" % [node_path, target.get_class()]}

    return {
        "status": "ok",
        "result": {
            "node_path": String(target.get_path()),
            "coords": {"x": coords.x, "y": coords.y},
            "source_id": source_id,
            "atlas_coords": {"x": atlas_coords.x, "y": atlas_coords.y},
            "alternative_tile": alternative_tile
        }
    }

func configure_navigation_region_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Target node not found: " + node_path}

    var navmesh_path = params.get("navmesh_path", params.get("navigation_mesh_path", params.get("resource_path", "")))
    var is_3d = (target is NavigationRegion3D) or (not (target is NavigationRegion2D) and params.get("is_3d", true))
    var resource_type = "NavigationMesh"

    if is_3d or target is NavigationRegion3D:
        var nav_mesh: NavigationMesh = null
        if navmesh_path != "" and FileAccess.file_exists(navmesh_path):
            nav_mesh = ResourceLoader.load(navmesh_path) as NavigationMesh
        if not nav_mesh and target is NavigationRegion3D and target.navigation_mesh:
            nav_mesh = target.navigation_mesh
        if not nav_mesh:
            nav_mesh = NavigationMesh.new()

        var nav_props = params.get("navigation_mesh_properties", params.get("mesh_properties", {}))
        for k in nav_props:
            nav_mesh.set(k, parse_variant(nav_props[k]))

        if target is NavigationRegion3D:
            if undo_redo_manager:
                var old_mesh = target.navigation_mesh
                undo_redo_manager.create_action("Configure NavigationRegion3D Mesh")
                undo_redo_manager.add_do_property(target, "navigation_mesh", nav_mesh)
                undo_redo_manager.add_undo_property(target, "navigation_mesh", old_mesh)
                undo_redo_manager.commit_action()
            else:
                target.navigation_mesh = nav_mesh

            if params.get("bake", false) and target.has_method("bake_navigation_mesh"):
                target.bake_navigation_mesh()

        resource_type = "NavigationMesh"
    else:
        var nav_poly: NavigationPolygon = null
        if navmesh_path != "" and FileAccess.file_exists(navmesh_path):
            nav_poly = ResourceLoader.load(navmesh_path) as NavigationPolygon
        if not nav_poly and target is NavigationRegion2D and target.navigation_polygon:
            nav_poly = target.navigation_polygon
        if not nav_poly:
            nav_poly = NavigationPolygon.new()

        var nav_props = params.get("navigation_mesh_properties", params.get("mesh_properties", {}))
        for k in nav_props:
            nav_poly.set(k, parse_variant(nav_props[k]))

        if target is NavigationRegion2D:
            if undo_redo_manager:
                var old_poly = target.navigation_polygon
                undo_redo_manager.create_action("Configure NavigationRegion2D Polygon")
                undo_redo_manager.add_do_property(target, "navigation_polygon", nav_poly)
                undo_redo_manager.add_undo_property(target, "navigation_polygon", old_poly)
                undo_redo_manager.commit_action()
            else:
                target.navigation_polygon = nav_poly

            if params.get("bake", false) and target.has_method("bake_navigation_polygon"):
                target.bake_navigation_polygon()

        resource_type = "NavigationPolygon"

    var region_props = params.get("region_properties", params.get("properties", {}))
    for k in region_props:
        var val = parse_variant(region_props[k])
        if undo_redo_manager:
            var old_val = target.get(k)
            undo_redo_manager.create_action("Set Region Property " + k)
            undo_redo_manager.add_do_property(target, k, val)
            undo_redo_manager.add_undo_property(target, k, old_val)
            undo_redo_manager.commit_action()
        else:
            target.set(k, val)

    return {
        "status": "ok",
        "result": {
            "node_path": String(target.get_path()),
            "node_class": target.get_class(),
            "resource_type": resource_type
        }
    }

func set_gridmap_cell_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Target node not found: " + node_path}

    if not (target is GridMap):
        return {"status": "error", "error": "Target node '%s' (%s) is not a GridMap" % [node_path, target.get_class()]}

    var pos = parse_gridmap_pos(params)
    var item = int(params.get("item", params.get("item_id", 0)))
    var orientation = int(params.get("orientation", 0))

    var mesh_lib_path = params.get("mesh_library_path", params.get("mesh_library", ""))
    if mesh_lib_path != "" and FileAccess.file_exists(mesh_lib_path):
        var mesh_lib = ResourceLoader.load(mesh_lib_path) as MeshLibrary
        if mesh_lib:
            target.mesh_library = mesh_lib

    if undo_redo_manager:
        var old_item = target.get_cell_item(pos)
        var old_orient = target.get_cell_item_orientation(pos)
        undo_redo_manager.create_action("Set GridMap Cell")
        undo_redo_manager.add_do_method(target, "set_cell_item", pos, item, orientation)
        undo_redo_manager.add_undo_method(target, "set_cell_item", pos, old_item, old_orient)
        undo_redo_manager.commit_action()
    else:
        target.set_cell_item(pos, item, orientation)

    return {
        "status": "ok",
        "result": {
            "node_path": String(target.get_path()),
            "position": {"x": pos.x, "y": pos.y, "z": pos.z},
            "item": item,
            "orientation": orientation
        }
    }

func parse_cell_coords(params: Dictionary) -> Vector2i:
    if params.has("coords"):
        return parse_vector2i(params["coords"])
    elif params.has("x") and params.has("y"):
        return Vector2i(int(params["x"]), int(params["y"]))
    elif params.has("coords_x") and params.has("coords_y"):
        return Vector2i(int(params["coords_x"]), int(params["coords_y"]))
    return Vector2i.ZERO

func parse_atlas_coords(params: Dictionary) -> Vector2i:
    if params.has("atlas_coords"):
        return parse_vector2i(params["atlas_coords"], Vector2i(-1, -1))
    elif params.has("atlas_x") and params.has("atlas_y"):
        return Vector2i(int(params["atlas_x"]), int(params["atlas_y"]))
    return Vector2i(-1, -1)

func parse_gridmap_pos(params: Dictionary) -> Vector3i:
    if params.has("position"):
        return parse_vector3i(params["position"])
    elif params.has("coords"):
        return parse_vector3i(params["coords"])
    elif params.has("x") and params.has("y") and params.has("z"):
        return Vector3i(int(params["x"]), int(params["y"]), int(params["z"]))
    return Vector3i.ZERO

func parse_vector2i(val, default_val: Vector2i = Vector2i.ZERO) -> Vector2i:
    if typeof(val) == TYPE_VECTOR2I:
        return val
    elif typeof(val) == TYPE_VECTOR2:
        return Vector2i(val)
    elif typeof(val) == TYPE_DICTIONARY:
        return Vector2i(int(val.get("x", default_val.x)), int(val.get("y", default_val.y)))
    elif typeof(val) == TYPE_ARRAY and val.size() >= 2:
        return Vector2i(int(val[0]), int(val[1]))
    return default_val

func parse_vector3i(val, default_val: Vector3i = Vector3i.ZERO) -> Vector3i:
    if typeof(val) == TYPE_VECTOR3I:
        return val
    elif typeof(val) == TYPE_VECTOR3:
        return Vector3i(val)
    elif typeof(val) == TYPE_DICTIONARY:
        return Vector3i(int(val.get("x", default_val.x)), int(val.get("y", default_val.y)), int(val.get("z", default_val.z)))
    elif typeof(val) == TYPE_ARRAY and val.size() >= 3:
        return Vector3i(int(val[0]), int(val[1]), int(val[2]))
    return default_val

func parse_vector2(val, default_val: Vector2 = Vector2.ZERO) -> Vector2:
    if typeof(val) == TYPE_VECTOR2:
        return val
    elif typeof(val) == TYPE_DICTIONARY:
        return Vector2(float(val.get("x", default_val.x)), float(val.get("y", default_val.y)))
    elif typeof(val) == TYPE_ARRAY and val.size() >= 2:
        return Vector2(float(val[0]), float(val[1]))
    return default_val

func parse_vector3(val, default_val: Vector3 = Vector3.ZERO) -> Vector3:
    if typeof(val) == TYPE_VECTOR3:
        return val
    elif typeof(val) == TYPE_DICTIONARY:
        return Vector3(float(val.get("x", default_val.x)), float(val.get("y", default_val.y)), float(val.get("z", default_val.z)))
    elif typeof(val) == TYPE_ARRAY and val.size() >= 3:
        return Vector3(float(val[0]), float(val[1]), float(val[2]))
    return default_val

func create_shape_resource(shape_type: String, shape_params: Dictionary, is_3d: bool) -> Resource:
    var st = shape_type.to_lower()
    if is_3d:
        match st:
            "box", "rectangle":
                var shape = BoxShape3D.new()
                shape.size = parse_vector3(shape_params.get("size", Vector3(1, 1, 1)))
                return shape
            "sphere", "circle":
                var shape = SphereShape3D.new()
                shape.radius = float(shape_params.get("radius", 0.5))
                return shape
            "capsule":
                var shape = CapsuleShape3D.new()
                shape.radius = float(shape_params.get("radius", 0.5))
                shape.height = float(shape_params.get("height", 2.0))
                return shape
            "cylinder":
                var shape = CylinderShape3D.new()
                shape.radius = float(shape_params.get("radius", 0.5))
                shape.height = float(shape_params.get("height", 2.0))
                return shape
            "worldboundary", "world_boundary":
                var shape = WorldBoundaryShape3D.new()
                var norm = parse_vector3(shape_params.get("normal", Vector3.UP))
                var d = float(shape_params.get("d", shape_params.get("distance", 0.0)))
                shape.plane = Plane(norm, d)
                return shape
            "convexpolygon", "convex_polygon":
                var shape = ConvexPolygonShape3D.new()
                var pts_raw = shape_params.get("points", [])
                var pts = PackedVector3Array()
                for p in pts_raw:
                    pts.append(parse_vector3(p))
                shape.points = pts
                return shape
            "concavepolygon", "concave_polygon":
                var shape = ConcavePolygonShape3D.new()
                var pts_raw = shape_params.get("points", shape_params.get("faces", []))
                var pts = PackedVector3Array()
                for p in pts_raw:
                    pts.append(parse_vector3(p))
                shape.set_faces(pts)
                return shape
            "segment":
                var shape = SeparationRayShape3D.new()
                shape.length = float(shape_params.get("length", 1.0))
                return shape
            _:
                var shape = BoxShape3D.new()
                shape.size = parse_vector3(shape_params.get("size", Vector3(1, 1, 1)))
                return shape
    else:
        match st:
            "box", "rectangle":
                var shape = RectangleShape2D.new()
                shape.size = parse_vector2(shape_params.get("size", Vector2(32, 32)))
                return shape
            "sphere", "circle":
                var shape = CircleShape2D.new()
                shape.radius = float(shape_params.get("radius", 16.0))
                return shape
            "capsule", "cylinder":
                var shape = CapsuleShape2D.new()
                shape.radius = float(shape_params.get("radius", 10.0))
                shape.height = float(shape_params.get("height", 30.0))
                return shape
            "segment":
                var shape = SegmentShape2D.new()
                shape.a = parse_vector2(shape_params.get("a", Vector2.ZERO))
                shape.b = parse_vector2(shape_params.get("b", Vector2(0, 10)))
                return shape
            "worldboundary", "world_boundary":
                var shape = WorldBoundaryShape2D.new()
                shape.normal = parse_vector2(shape_params.get("normal", Vector2.UP))
                shape.distance = float(shape_params.get("d", shape_params.get("distance", 0.0)))
                return shape
            "convexpolygon", "convex_polygon":
                var shape = ConvexPolygonShape2D.new()
                var pts_raw = shape_params.get("points", [])
                var pts = PackedVector2Array()
                for p in pts_raw:
                    pts.append(parse_vector2(p))
                shape.points = pts
                return shape
            "concavepolygon", "concave_polygon":
                var shape = ConcavePolygonShape2D.new()
                var pts_raw = shape_params.get("points", shape_params.get("segments", []))
                var pts = PackedVector2Array()
                for p in pts_raw:
                    pts.append(parse_vector2(p))
                shape.segments = pts
                return shape
            _:
                var shape = RectangleShape2D.new()
                shape.size = parse_vector2(shape_params.get("size", Vector2(32, 32)))
                return shape

func configure_physics_body_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var body_type = params.get("body_type", "")
    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)

    var is_3d = params.get("is_3d", false)
    if not is_3d and body_type.ends_with("3D"):
        is_3d = true

    if not target:
        if body_type != "" and ClassDB.class_exists(body_type):
            target = ClassDB.instantiate(body_type) as Node
            var name_parts = node_path.split("/")
            target.name = name_parts[name_parts.size() - 1] if name_parts.size() > 0 else body_type
            var parent = root
            if name_parts.size() > 1:
                var parent_path = node_path.substr(0, node_path.rfind("/"))
                parent = root.get_node_or_null(parent_path)
                if not parent: parent = root

            if undo_redo_manager:
                undo_redo_manager.create_action("Add " + body_type + " " + target.name)
                undo_redo_manager.add_do_method(parent, "add_child", target)
                undo_redo_manager.add_do_method(target, "set_owner", root)
                undo_redo_manager.add_do_reference(target)
                undo_redo_manager.add_undo_method(parent, "remove_child", target)
                undo_redo_manager.commit_action()
            else:
                parent.add_child(target)
                target.owner = root
        else:
            return {"status": "error", "error": "Target physics body node not found at: " + node_path}

    var changes = []

    if params.has("collision_layer"):
        var layer = int(params["collision_layer"])
        if undo_redo_manager:
            var old_val = target.get("collision_layer")
            undo_redo_manager.create_action("Set collision_layer on " + target.name)
            undo_redo_manager.add_do_property(target, "collision_layer", layer)
            undo_redo_manager.add_undo_property(target, "collision_layer", old_val)
            undo_redo_manager.commit_action()
        else:
            target.set("collision_layer", layer)
        changes.append("collision_layer")

    if params.has("collision_mask"):
        var mask = int(params["collision_mask"])
        if undo_redo_manager:
            var old_val = target.get("collision_mask")
            undo_redo_manager.create_action("Set collision_mask on " + target.name)
            undo_redo_manager.add_do_property(target, "collision_mask", mask)
            undo_redo_manager.add_undo_property(target, "collision_mask", old_val)
            undo_redo_manager.commit_action()
        else:
            target.set("collision_mask", mask)
        changes.append("collision_mask")

    if params.has("mass") and "mass" in target:
        var mass_val = float(params["mass"])
        if undo_redo_manager:
            var old_val = target.get("mass")
            undo_redo_manager.create_action("Set mass on " + target.name)
            undo_redo_manager.add_do_property(target, "mass", mass_val)
            undo_redo_manager.add_undo_property(target, "mass", old_val)
            undo_redo_manager.commit_action()
        else:
            target.set("mass", mass_val)
        changes.append("mass")

    if params.has("gravity_scale") and "gravity_scale" in target:
        var grav_val = float(params["gravity_scale"])
        if undo_redo_manager:
            var old_val = target.get("gravity_scale")
            undo_redo_manager.create_action("Set gravity_scale on " + target.name)
            undo_redo_manager.add_do_property(target, "gravity_scale", grav_val)
            undo_redo_manager.add_undo_property(target, "gravity_scale", old_val)
            undo_redo_manager.commit_action()
        else:
            target.set("gravity_scale", grav_val)
        changes.append("gravity_scale")

    if params.has("friction") or params.has("bounce"):
        if "physics_material_override" in target:
            var phys_mat: PhysicsMaterial = target.physics_material_override
            if not phys_mat:
                phys_mat = PhysicsMaterial.new()
            if params.has("friction"):
                phys_mat.friction = float(params["friction"])
                changes.append("friction")
            if params.has("bounce"):
                phys_mat.bounce = float(params["bounce"])
                changes.append("bounce")

            if undo_redo_manager:
                var old_mat = target.physics_material_override
                undo_redo_manager.create_action("Set physics_material_override on " + target.name)
                undo_redo_manager.add_do_property(target, "physics_material_override", phys_mat)
                undo_redo_manager.add_undo_property(target, "physics_material_override", old_mat)
                undo_redo_manager.commit_action()
            else:
                target.physics_material_override = phys_mat
        else:
            if params.has("friction") and "friction" in target:
                target.set("friction", float(params["friction"]))
                changes.append("friction")
            if params.has("bounce") and "bounce" in target:
                target.set("bounce", float(params["bounce"]))
                changes.append("bounce")

    return {
        "status": "ok",
        "result": {
            "node_path": String(target.get_path()),
            "node_class": target.get_class(),
            "configured_properties": changes
        }
    }

func add_collision_shape_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var parent_path = params.get("parent_path", params.get("node_path", "."))
    var shape_type = params.get("shape_type", "Box")
    var shape_params = params.get("shape_params", {})
    var node_name = params.get("node_name", "")

    var parent = root if (parent_path == "." or parent_path == "") else root.get_node_or_null(parent_path)
    if not parent:
        return {"status": "error", "error": "Parent node not found at: " + parent_path}

    var is_3d = params.get("is_3d", false)
    if not params.has("is_3d"):
        if parent is Node3D or parent is CollisionObject3D:
            is_3d = true
        elif ["sphere", "cylinder"].has(shape_type.to_lower()):
            is_3d = true

    var shape_res = create_shape_resource(shape_type, shape_params, is_3d)

    var col_node: Node = null
    if is_3d:
        var col3d = CollisionShape3D.new()
        col3d.shape = shape_res as Shape3D
        col_node = col3d
        if node_name == "": node_name = "CollisionShape3D"
    else:
        var col2d = CollisionShape2D.new()
        col2d.shape = shape_res as Shape2D
        col_node = col2d
        if node_name == "": node_name = "CollisionShape2D"

    col_node.name = node_name

    if undo_redo_manager:
        undo_redo_manager.create_action("Add Collision Shape " + node_name)
        undo_redo_manager.add_do_method(parent, "add_child", col_node)
        undo_redo_manager.add_do_method(col_node, "set_owner", root)
        undo_redo_manager.add_do_reference(col_node)
        undo_redo_manager.add_undo_method(parent, "remove_child", col_node)
        undo_redo_manager.commit_action()
    else:
        parent.add_child(col_node)
        col_node.owner = root

    return {
        "status": "ok",
        "result": {
            "node_name": col_node.name,
            "node_path": String(col_node.get_path()),
            "shape_type": shape_type,
            "is_3d": is_3d
        }
    }

func configure_raycast_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)

    var is_3d = params.get("is_3d", false)
    if not target:
        if is_3d or node_path.ends_with("3D"):
            target = RayCast3D.new()
        else:
            target = RayCast2D.new()
        var name_parts = node_path.split("/")
        target.name = name_parts[name_parts.size() - 1]
        var parent = root
        if name_parts.size() > 1:
            var parent_path = node_path.substr(0, node_path.rfind("/"))
            parent = root.get_node_or_null(parent_path)
            if not parent: parent = root

        if undo_redo_manager:
            undo_redo_manager.create_action("Add RayCast " + target.name)
            undo_redo_manager.add_do_method(parent, "add_child", target)
            undo_redo_manager.add_do_method(target, "set_owner", root)
            undo_redo_manager.add_do_reference(target)
            undo_redo_manager.add_undo_method(parent, "remove_child", target)
            undo_redo_manager.commit_action()
        else:
            parent.add_child(target)
            target.owner = root

    var changes = []

    if params.has("target_position"):
        var raw_tp = params["target_position"]
        var tp_val
        if target is RayCast3D:
            tp_val = parse_vector3(raw_tp)
        else:
            tp_val = parse_vector2(raw_tp)

        if undo_redo_manager:
            var old_val = target.get("target_position")
            undo_redo_manager.create_action("Set target_position on " + target.name)
            undo_redo_manager.add_do_property(target, "target_position", tp_val)
            undo_redo_manager.add_undo_property(target, "target_position", old_val)
            undo_redo_manager.commit_action()
        else:
            target.set("target_position", tp_val)
        changes.append("target_position")

    for prop_name in ["collide_with_bodies", "collide_with_areas", "enabled"]:
        if params.has(prop_name):
            var b_val = bool(params[prop_name])
            if undo_redo_manager:
                var old_val = target.get(prop_name)
                undo_redo_manager.create_action("Set " + prop_name + " on " + target.name)
                undo_redo_manager.add_do_property(target, prop_name, b_val)
                undo_redo_manager.add_undo_property(target, prop_name, old_val)
                undo_redo_manager.commit_action()
            else:
                target.set(prop_name, b_val)
            changes.append(prop_name)

    if params.has("collision_mask"):
        var mask_val = int(params["collision_mask"])
        if undo_redo_manager:
            var old_val = target.get("collision_mask")
            undo_redo_manager.create_action("Set collision_mask on " + target.name)
            undo_redo_manager.add_do_property(target, "collision_mask", mask_val)
            undo_redo_manager.add_undo_property(target, "collision_mask", old_val)
            undo_redo_manager.commit_action()
        else:
            target.set("collision_mask", mask_val)
        changes.append("collision_mask")

    return {
        "status": "ok",
        "result": {
            "node_path": String(target.get_path()),
            "node_class": target.get_class(),
            "configured_properties": changes
        }
    }

func configure_area_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)

    var is_3d = params.get("is_3d", false)
    if not target:
        if is_3d or node_path.ends_with("3D"):
            target = Area3D.new()
        else:
            target = Area2D.new()
        var name_parts = node_path.split("/")
        target.name = name_parts[name_parts.size() - 1]
        var parent = root
        if name_parts.size() > 1:
            var parent_path = node_path.substr(0, node_path.rfind("/"))
            parent = root.get_node_or_null(parent_path)
            if not parent: parent = root

        if undo_redo_manager:
            undo_redo_manager.create_action("Add Area " + target.name)
            undo_redo_manager.add_do_method(parent, "add_child", target)
            undo_redo_manager.add_do_method(target, "set_owner", root)
            undo_redo_manager.add_do_reference(target)
            undo_redo_manager.add_undo_method(parent, "remove_child", target)
            undo_redo_manager.commit_action()
        else:
            parent.add_child(target)
            target.owner = root

    var changes = []

    for prop_name in ["monitoring", "monitorable"]:
        if params.has(prop_name):
            var b_val = bool(params[prop_name])
            if undo_redo_manager:
                var old_val = target.get(prop_name)
                undo_redo_manager.create_action("Set " + prop_name + " on " + target.name)
                undo_redo_manager.add_do_property(target, prop_name, b_val)
                undo_redo_manager.add_undo_property(target, prop_name, old_val)
                undo_redo_manager.commit_action()
            else:
                target.set(prop_name, b_val)
            changes.append(prop_name)

    if params.has("priority"):
        var p_val = int(params["priority"])
        if undo_redo_manager:
            var old_val = target.get("priority")
            undo_redo_manager.create_action("Set priority on " + target.name)
            undo_redo_manager.add_do_property(target, "priority", p_val)
            undo_redo_manager.add_undo_property(target, "priority", old_val)
            undo_redo_manager.commit_action()
        else:
            target.set("priority", p_val)
        changes.append("priority")

    if params.has("gravity"):
        var g_val = float(params["gravity"])
        if undo_redo_manager:
            var old_val = target.get("gravity")
            undo_redo_manager.create_action("Set gravity on " + target.name)
            undo_redo_manager.add_do_property(target, "gravity", g_val)
            undo_redo_manager.add_undo_property(target, "gravity", old_val)
            undo_redo_manager.commit_action()
        else:
            target.set("gravity", g_val)
        changes.append("gravity")

    if params.has("collision_layer"):
        var l_val = int(params["collision_layer"])
        if undo_redo_manager:
            var old_val = target.get("collision_layer")
            undo_redo_manager.create_action("Set collision_layer on " + target.name)
            undo_redo_manager.add_do_property(target, "collision_layer", l_val)
            undo_redo_manager.add_undo_property(target, "collision_layer", old_val)
            undo_redo_manager.commit_action()
        else:
            target.set("collision_layer", l_val)
        changes.append("collision_layer")

    if params.has("collision_mask"):
        var m_val = int(params["collision_mask"])
        if undo_redo_manager:
            var old_val = target.get("collision_mask")
            undo_redo_manager.create_action("Set collision_mask on " + target.name)
            undo_redo_manager.add_do_property(target, "collision_mask", m_val)
            undo_redo_manager.add_undo_property(target, "collision_mask", old_val)
            undo_redo_manager.commit_action()
        else:
            target.set("collision_mask", m_val)
        changes.append("collision_mask")

    return {
        "status": "ok",
        "result": {
            "node_path": String(target.get_path()),
            "node_class": target.get_class(),
            "configured_properties": changes
        }
    }

func _parse_layout_preset(preset_val) -> int:
    if typeof(preset_val) == TYPE_INT or typeof(preset_val) == TYPE_FLOAT:
        return int(preset_val)
    if typeof(preset_val) == TYPE_STRING:
        var s = (preset_val as String).strip_edges().to_upper()
        if s.begins_with("PRESET_"):
            s = s.substr(7)
        match s:
            "TOP_LEFT", "TOPLEFT": return Control.PRESET_TOP_LEFT
            "TOP_RIGHT", "TOPRIGHT": return Control.PRESET_TOP_RIGHT
            "BOTTOM_LEFT", "BOTTOMLEFT": return Control.PRESET_BOTTOM_LEFT
            "BOTTOM_RIGHT", "BOTTOMRIGHT": return Control.PRESET_BOTTOM_RIGHT
            "CENTER_LEFT", "CENTERLEFT": return Control.PRESET_CENTER_LEFT
            "CENTER_TOP", "CENTERTOP": return Control.PRESET_CENTER_TOP
            "CENTER_RIGHT", "CENTERRIGHT": return Control.PRESET_CENTER_RIGHT
            "CENTER_BOTTOM", "CENTERBOTTOM": return Control.PRESET_CENTER_BOTTOM
            "CENTER": return Control.PRESET_CENTER
            "LEFT_WIDE", "LEFTWIDE": return Control.PRESET_LEFT_WIDE
            "TOP_WIDE", "TOPWIDE": return Control.PRESET_TOP_WIDE
            "RIGHT_WIDE", "RIGHTWIDE": return Control.PRESET_RIGHT_WIDE
            "BOTTOM_WIDE", "BOTTOMWIDE": return Control.PRESET_BOTTOM_WIDE
            "VCENTER_WIDE", "VCENTERWIDE": return Control.PRESET_VCENTER_WIDE
            "HCENTER_WIDE", "HCENTERWIDE": return Control.PRESET_HCENTER_WIDE
            "FULL_RECT", "FULLRECT", "WIDE": return Control.PRESET_FULL_RECT
            _:
                if s.is_valid_int():
                    return s.to_int()
    return Control.PRESET_FULL_RECT

func _apply_theme_override(ctrl: Control, override_type: String, override_name: String, val) -> Error:
    var t = override_type.to_lower().strip_edges()
    var is_clear = (val == null or (val is String and (val == "" or val == "clear" or val == "remove")))

    match t:
        "color":
            if is_clear:
                ctrl.remove_theme_color_override(override_name)
            else:
                var col: Color = Color.WHITE
                if val is Color:
                    col = val
                elif val is String:
                    col = Color(val)
                elif val is Dictionary:
                    col = Color(float(val.get("r", 0)), float(val.get("g", 0)), float(val.get("b", 0)), float(val.get("a", 1)))
                ctrl.add_theme_color_override(override_name, col)
        "font":
            if is_clear:
                ctrl.remove_theme_font_override(override_name)
            else:
                var f: Font = null
                if val is Font:
                    f = val
                elif val is String and FileAccess.file_exists(val):
                    f = ResourceLoader.load(val) as Font
                if f:
                    ctrl.add_theme_font_override(override_name, f)
                else:
                    return ERR_INVALID_DATA
        "font_size":
            if is_clear:
                ctrl.remove_theme_font_size_override(override_name)
            else:
                ctrl.add_theme_font_size_override(override_name, int(val))
        "constant":
            if is_clear:
                ctrl.remove_theme_constant_override(override_name)
            else:
                ctrl.add_theme_constant_override(override_name, int(val))
        "stylebox":
            if is_clear:
                ctrl.remove_theme_stylebox_override(override_name)
            else:
                var sb: StyleBox = null
                if val is StyleBox:
                    sb = val
                elif val is String and FileAccess.file_exists(val):
                    sb = ResourceLoader.load(val) as StyleBox
                elif val is Dictionary:
                    var sb_flat = StyleBoxFlat.new()
                    for k in val:
                        sb_flat.set(k, parse_variant(val[k]))
                    sb = sb_flat
                if sb:
                    ctrl.add_theme_stylebox_override(override_name, sb)
                else:
                    return ERR_INVALID_DATA
        _:
            return ERR_METHOD_NOT_FOUND
    return OK

func create_ui_layout_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var parent_path = params.get("parent_path", params.get("node_path", "."))
    var container_type = params.get("container_type", params.get("layout_type", "VBoxContainer"))
    var container_name = params.get("container_name", params.get("name", container_type))
    var layout_preset = params.get("layout_preset", null)
    var controls_to_add = params.get("controls_to_add", params.get("controls", []))

    var parent = root if (parent_path == "." or parent_path == "" or parent_path == "root") else root.get_node_or_null(parent_path)
    if not parent:
        return {"status": "error", "error": "Parent node not found at path: " + parent_path}

    if not ClassDB.class_exists(container_type):
        return {"status": "error", "error": "Invalid container_type class: " + container_type}

    var container = ClassDB.instantiate(container_type) as Node
    container.name = container_name

    if container is Control and layout_preset != null:
        container.set_anchors_preset(_parse_layout_preset(layout_preset))

    var added_controls = []
    var created_nodes = [container]

    if controls_to_add is Array:
        for item in controls_to_add:
            var ctype = "Control"
            var cname = ""
            var ctext = ""
            var cprops = {}
            if item is String:
                ctype = item
            elif item is Dictionary:
                ctype = item.get("type", item.get("class", "Control"))
                cname = item.get("name", "")
                ctext = item.get("text", "")
                cprops = item.get("properties", {})

            if not ClassDB.class_exists(ctype):
                continue

            var cnode = ClassDB.instantiate(ctype) as Node
            if cname != "":
                cnode.name = cname
            if ctext != "" and cnode.has_method("set_text"):
                cnode.call("set_text", ctext)
            elif ctext != "" and "text" in cnode:
                cnode.set("text", ctext)

            for p in cprops:
                cnode.set(p, parse_variant(cprops[p]))

            container.add_child(cnode)
            created_nodes.append(cnode)
            added_controls.append({"name": cnode.name, "type": ctype})

    if undo_redo_manager:
        undo_redo_manager.create_action("Create UI Layout")
        undo_redo_manager.add_do_method(parent, "add_child", container)
        for n in created_nodes:
            undo_redo_manager.add_do_method(n, "set_owner", root)
            undo_redo_manager.add_do_reference(n)
        undo_redo_manager.add_undo_method(parent, "remove_child", container)
        undo_redo_manager.commit_action()
    else:
        parent.add_child(container)
        for n in created_nodes:
            n.owner = root

    return {
        "status": "ok",
        "result": {
            "container_path": String(container.get_path()),
            "container_type": container_type,
            "container_name": container.name,
            "added_controls": added_controls
        }
    }

func apply_theme_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var theme_path = params.get("theme_path", "")
    var target_node_path = params.get("target_node_path", params.get("node_path", "."))

    if theme_path == "" or not FileAccess.file_exists(theme_path):
        return {"status": "error", "error": "Invalid or missing theme_path: " + theme_path}

    var theme = ResourceLoader.load(theme_path) as Theme
    if not theme:
        return {"status": "error", "error": "Failed to load Theme resource at " + theme_path}

    var target = root if (target_node_path == "." or target_node_path == "" or target_node_path == "root") else root.get_node_or_null(target_node_path)
    if not target:
        return {"status": "error", "error": "Target node not found at path: " + target_node_path}

    if target is Control:
        if undo_redo_manager:
            var old_theme = target.theme
            undo_redo_manager.create_action("Apply Theme")
            undo_redo_manager.add_do_property(target, "theme", theme)
            undo_redo_manager.add_undo_property(target, "theme", old_theme)
            undo_redo_manager.commit_action()
        else:
            target.theme = theme
    elif "theme" in target:
        if undo_redo_manager:
            var old_theme = target.get("theme")
            undo_redo_manager.create_action("Apply Theme")
            undo_redo_manager.add_do_property(target, "theme", theme)
            undo_redo_manager.add_undo_property(target, "theme", old_theme)
            undo_redo_manager.commit_action()
        else:
            target.set("theme", theme)
    else:
        return {"status": "error", "error": "Target node does not support theme property"}

    return {
        "status": "ok",
        "result": {
            "target_node_path": String(target.get_path()),
            "theme_path": theme_path
        }
    }

func configure_control_anchors_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var anchor_preset = params.get("anchor_preset", null)
    var custom_anchors = params.get("custom_anchors", {})
    var custom_offsets = params.get("custom_offsets", {})

    var target = root if (node_path == "." or node_path == "" or node_path == "root") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Target node not found at path: " + node_path}

    if not target is Control:
        return {"status": "error", "error": "Target node is not a Control: " + node_path}

    var ctrl = target as Control

    if undo_redo_manager:
        undo_redo_manager.create_action("Configure Control Anchors")
        if anchor_preset != null:
            var p_idx = _parse_layout_preset(anchor_preset)
            undo_redo_manager.add_do_method(ctrl, "set_anchors_preset", p_idx)

        if custom_anchors is Dictionary:
            if custom_anchors.has("left"): undo_redo_manager.add_do_property(ctrl, "anchor_left", float(custom_anchors["left"]))
            if custom_anchors.has("anchor_left"): undo_redo_manager.add_do_property(ctrl, "anchor_left", float(custom_anchors["anchor_left"]))
            if custom_anchors.has("top"): undo_redo_manager.add_do_property(ctrl, "anchor_top", float(custom_anchors["top"]))
            if custom_anchors.has("anchor_top"): undo_redo_manager.add_do_property(ctrl, "anchor_top", float(custom_anchors["anchor_top"]))
            if custom_anchors.has("right"): undo_redo_manager.add_do_property(ctrl, "anchor_right", float(custom_anchors["right"]))
            if custom_anchors.has("anchor_right"): undo_redo_manager.add_do_property(ctrl, "anchor_right", float(custom_anchors["anchor_right"]))
            if custom_anchors.has("bottom"): undo_redo_manager.add_do_property(ctrl, "anchor_bottom", float(custom_anchors["bottom"]))
            if custom_anchors.has("anchor_bottom"): undo_redo_manager.add_do_property(ctrl, "anchor_bottom", float(custom_anchors["anchor_bottom"]))

        if custom_offsets is Dictionary:
            if custom_offsets.has("left"): undo_redo_manager.add_do_property(ctrl, "offset_left", float(custom_offsets["left"]))
            if custom_offsets.has("offset_left"): undo_redo_manager.add_do_property(ctrl, "offset_left", float(custom_offsets["offset_left"]))
            if custom_offsets.has("top"): undo_redo_manager.add_do_property(ctrl, "offset_top", float(custom_offsets["top"]))
            if custom_offsets.has("offset_top"): undo_redo_manager.add_do_property(ctrl, "offset_top", float(custom_offsets["offset_top"]))
            if custom_offsets.has("right"): undo_redo_manager.add_do_property(ctrl, "offset_right", float(custom_offsets["right"]))
            if custom_offsets.has("offset_right"): undo_redo_manager.add_do_property(ctrl, "offset_right", float(custom_offsets["offset_right"]))
            if custom_offsets.has("bottom"): undo_redo_manager.add_do_property(ctrl, "offset_bottom", float(custom_offsets["bottom"]))
            if custom_offsets.has("offset_bottom"): undo_redo_manager.add_do_property(ctrl, "offset_bottom", float(custom_offsets["offset_bottom"]))

        undo_redo_manager.commit_action()
    else:
        if anchor_preset != null:
            ctrl.set_anchors_preset(_parse_layout_preset(anchor_preset))

        if custom_anchors is Dictionary:
            if custom_anchors.has("left"): ctrl.anchor_left = float(custom_anchors["left"])
            if custom_anchors.has("anchor_left"): ctrl.anchor_left = float(custom_anchors["anchor_left"])
            if custom_anchors.has("top"): ctrl.anchor_top = float(custom_anchors["top"])
            if custom_anchors.has("anchor_top"): ctrl.anchor_top = float(custom_anchors["anchor_top"])
            if custom_anchors.has("right"): ctrl.anchor_right = float(custom_anchors["right"])
            if custom_anchors.has("anchor_right"): ctrl.anchor_right = float(custom_anchors["anchor_right"])
            if custom_anchors.has("bottom"): ctrl.anchor_bottom = float(custom_anchors["bottom"])
            if custom_anchors.has("anchor_bottom"): ctrl.anchor_bottom = float(custom_anchors["anchor_bottom"])

        if custom_offsets is Dictionary:
            if custom_offsets.has("left"): ctrl.offset_left = float(custom_offsets["left"])
            if custom_offsets.has("offset_left"): ctrl.offset_left = float(custom_offsets["offset_left"])
            if custom_offsets.has("top"): ctrl.offset_top = float(custom_offsets["top"])
            if custom_offsets.has("offset_top"): ctrl.offset_top = float(custom_offsets["offset_top"])
            if custom_offsets.has("right"): ctrl.offset_right = float(custom_offsets["right"])
            if custom_offsets.has("offset_right"): ctrl.offset_right = float(custom_offsets["offset_right"])
            if custom_offsets.has("bottom"): ctrl.offset_bottom = float(custom_offsets["bottom"])
            if custom_offsets.has("offset_bottom"): ctrl.offset_bottom = float(custom_offsets["offset_bottom"])

    return {
        "status": "ok",
        "result": {
            "node_path": String(ctrl.get_path()),
            "anchors": {
                "left": ctrl.anchor_left,
                "top": ctrl.anchor_top,
                "right": ctrl.anchor_right,
                "bottom": ctrl.anchor_bottom
            },
            "offsets": {
                "left": ctrl.offset_left,
                "top": ctrl.offset_top,
                "right": ctrl.offset_right,
                "bottom": ctrl.offset_bottom
            }
        }
    }

func set_control_theme_override_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var node_path = params.get("node_path", ".")
    var override_type = params.get("override_type", "")
    var override_name = params.get("override_name", "")
    var value = params.get("value", null)

    if override_type == "" or override_name == "":
        return {"status": "error", "error": "Missing override_type or override_name"}

    var target = root if (node_path == "." or node_path == "" or node_path == "root") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Target node not found at path: " + node_path}

    if not target is Control:
        return {"status": "error", "error": "Target node is not a Control: " + node_path}

    var err = _apply_theme_override(target as Control, override_type, override_name, value)
    if err != OK:
        return {"status": "error", "error": "Failed to set theme override '%s' of type '%s'" % [override_name, override_type]}

    return {
        "status": "ok",
        "result": {
            "node_path": String(target.get_path()),
            "override_type": override_type,
            "override_name": override_name
        }
    }

func find_first_node_of_class(parent: Node, target_class: String) -> Node:
    if parent.is_class(target_class) or parent.get_class() == target_class:
        return parent
    for child in parent.get_children():
        var found = find_first_node_of_class(child, target_class)
        if found:
            return found
    return null

func parse_track_type(type_val) -> int:
    if typeof(type_val) == TYPE_INT:
        return type_val
    var s = String(type_val).to_lower()
    match s:
        "value", "transform": return Animation.TYPE_VALUE
        "position_3d", "position": return Animation.TYPE_POSITION_3D
        "rotation_3d", "rotation": return Animation.TYPE_ROTATION_3D
        "scale_3d", "scale": return Animation.TYPE_SCALE_3D
        "blend_shape": return Animation.TYPE_BLEND_SHAPE
        "method": return Animation.TYPE_METHOD
        "bezier": return Animation.TYPE_BEZIER
        "audio": return Animation.TYPE_AUDIO
        "animation": return Animation.TYPE_ANIMATION
        _: return Animation.TYPE_VALUE

func get_animation_in_editor(params: Dictionary) -> Dictionary:
    var anim_path = params.get("animation_path", "")
    var anim_player_path = params.get("animation_player_path", params.get("anim_player_path", "AnimationPlayer"))
    var anim_name = params.get("animation_name", "new_animation")

    if anim_path != "" and FileAccess.file_exists(anim_path):
        var anim = ResourceLoader.load(anim_path) as Animation
        if anim:
            return {"anim": anim, "anim_path": anim_path, "type": "resource"}

    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if root:
        var player = root if anim_player_path == "." else root.get_node_or_null(anim_player_path)
        if not player or not (player is AnimationPlayer):
            player = find_first_node_of_class(root, "AnimationPlayer")
        if player and player is AnimationPlayer:
            if player.has_animation_library(""):
                var lib = player.get_animation_library("")
                if lib.has_animation(anim_name):
                    return {"anim": lib.get_animation(anim_name), "player": player, "anim_name": anim_name, "type": "editor_scene"}

    return {}

func save_modified_animation_in_editor(anim_ctx: Dictionary):
    var anim = anim_ctx.get("anim") as Animation
    if not anim: return
    
    if anim_ctx.get("type") == "resource" or anim_ctx.has("anim_path"):
        ResourceSaver.save(anim, anim_ctx["anim_path"])
        if editor_interface:
            editor_interface.get_resource_filesystem().scan()

func create_animation_in_editor(params: Dictionary) -> Dictionary:
    var anim_path = params.get("animation_path", "")
    var anim_player_path = params.get("animation_player_path", "AnimationPlayer")
    var anim_name = params.get("animation_name", "new_animation")
    var length = float(params.get("length", 1.0))
    var step = float(params.get("step", 0.1))
    var loop_val = params.get("loop_mode", 0)

    var anim = Animation.new()
    anim.length = length
    anim.step = step

    if typeof(loop_val) == TYPE_STRING:
        match String(loop_val).to_lower():
            "linear": anim.loop_mode = Animation.LOOP_LINEAR
            "pingpong": anim.loop_mode = Animation.LOOP_PINGPONG
            _: anim.loop_mode = Animation.LOOP_NONE
    else:
        anim.loop_mode = int(loop_val)

    if anim_path != "":
        var err = ResourceSaver.save(anim, anim_path)
        if err != OK:
            return {"status": "error", "error": "Failed to save animation resource: %d" % err}
        if editor_interface:
            editor_interface.get_resource_filesystem().scan()

    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if root:
        var player = root if anim_player_path == "." else root.get_node_or_null(anim_player_path)
        if not player or not (player is AnimationPlayer):
            player = find_first_node_of_class(root, "AnimationPlayer")
        if player and player is AnimationPlayer:
            var lib: AnimationLibrary
            if player.has_animation_library(""):
                lib = player.get_animation_library("")
            else:
                lib = AnimationLibrary.new()
                player.add_animation_library("", lib)
            if lib.has_animation(anim_name):
                lib.remove_animation(anim_name)
            lib.add_animation(anim_name, anim)

    return {
        "status": "ok",
        "result": {
            "animation_name": anim_name,
            "length": anim.length,
            "step": anim.step,
            "loop_mode": anim.loop_mode,
            "animation_path": anim_path
        }
    }

func add_animation_track_in_editor(params: Dictionary) -> Dictionary:
    var anim_ctx = get_animation_in_editor(params)
    if anim_ctx.is_empty():
        return {"status": "error", "error": "Animation not found in editor"}

    var anim = anim_ctx["anim"] as Animation
    var track_type_val = params.get("track_type", "value")
    var ttype = parse_track_type(track_type_val)
    var track_path_str = params.get("track_path", params.get("node_path", params.get("property_path", "")))

    var track_idx = anim.add_track(ttype)
    if track_path_str != "":
        anim.track_set_path(track_idx, NodePath(track_path_str))

    if params.has("interpolation_type"):
        var interp = params["interpolation_type"]
        if typeof(interp) == TYPE_STRING:
            match String(interp).to_lower():
                "nearest": anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_NEAREST)
                "linear": anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)
                "cubic": anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_CUBIC)
        else:
            anim.track_set_interpolation_type(track_idx, int(interp))

    if ttype == Animation.TYPE_VALUE and params.has("update_mode"):
        var upmode = params["update_mode"]
        if typeof(upmode) == TYPE_STRING:
            match String(upmode).to_lower():
                "continuous": anim.value_track_set_update_mode(track_idx, Animation.UPDATE_CONTINUOUS)
                "discrete": anim.value_track_set_update_mode(track_idx, Animation.UPDATE_DISCRETE)
                "capture": anim.value_track_set_update_mode(track_idx, Animation.UPDATE_CAPTURE)
        else:
            anim.value_track_set_update_mode(track_idx, int(upmode))

    save_modified_animation_in_editor(anim_ctx)

    return {
        "status": "ok",
        "result": {
            "track_index": track_idx,
            "track_type": ttype,
            "track_path": track_path_str
        }
    }

func insert_animation_keyframe_in_editor(params: Dictionary) -> Dictionary:
    var anim_ctx = get_animation_in_editor(params)
    if anim_ctx.is_empty():
        return {"status": "error", "error": "Animation not found in editor"}

    var anim = anim_ctx["anim"] as Animation
    var track_idx = params.get("track_index", -1)
    var track_path_str = params.get("track_path", "")

    if track_idx == -1 and track_path_str != "":
        var target_np = NodePath(track_path_str)
        for i in range(anim.get_track_count()):
            if anim.track_get_path(i) == target_np:
                track_idx = i
                break

    if track_idx < 0 or track_idx >= anim.get_track_count():
        return {"status": "error", "error": "Invalid track_index (%d) or track_path not found" % track_idx}

    var time = float(params.get("time", 0.0))
    var raw_value = params.get("value", null)
    var parsed_val = parse_variant(raw_value)
    var transition = float(params.get("transition", 1.0))

    var ttype = anim.track_get_type(track_idx)
    var key_idx = -1

    if ttype == Animation.TYPE_METHOD:
        var method_data = {}
        if typeof(parsed_val) == TYPE_DICTIONARY:
            method_data = {
                "method": parsed_val.get("method", ""),
                "args": parsed_val.get("args", [])
            }
        else:
            method_data = {"method": String(parsed_val), "args": []}
        key_idx = anim.track_insert_key(track_idx, time, method_data)
    elif ttype == Animation.TYPE_POSITION_3D or ttype == Animation.TYPE_SCALE_3D:
        if typeof(parsed_val) != TYPE_VECTOR3 and typeof(parsed_val) == TYPE_DICTIONARY:
            parsed_val = Vector3(parsed_val.get("x", 0), parsed_val.get("y", 0), parsed_val.get("z", 0))
        key_idx = anim.track_insert_key(track_idx, time, parsed_val, transition)
    elif ttype == Animation.TYPE_ROTATION_3D:
        if typeof(parsed_val) != TYPE_QUATERNION and typeof(parsed_val) == TYPE_DICTIONARY:
            parsed_val = Quaternion(parsed_val.get("x", 0), parsed_val.get("y", 0), parsed_val.get("z", 0), parsed_val.get("w", 1))
        key_idx = anim.track_insert_key(track_idx, time, parsed_val, transition)
    else:
        key_idx = anim.track_insert_key(track_idx, time, parsed_val, transition)

    save_modified_animation_in_editor(anim_ctx)

    return {
        "status": "ok",
        "result": {
            "track_index": track_idx,
            "time": time,
            "key_index": key_idx,
            "value": String(parsed_val)
        }
    }

func configure_animation_tree_in_editor(params: Dictionary) -> Dictionary:
    var root = editor_interface.get_edited_scene_root() if editor_interface else null
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}

    var anim_tree_path = params.get("animation_tree_path", params.get("node_path", "AnimationTree"))
    var anim_player_path = params.get("animation_player_path", params.get("anim_player_path", "AnimationPlayer"))
    var tree_type = params.get("tree_type", "AnimationNodeStateMachine")
    var active = params.get("active", true)

    var tree_node = root if anim_tree_path == "." else root.get_node_or_null(anim_tree_path)

    if not tree_node:
        tree_node = AnimationTree.new()
        tree_node.name = "AnimationTree"
        if undo_redo_manager:
            undo_redo_manager.create_action("Add AnimationTree")
            undo_redo_manager.add_do_method(root, "add_child", tree_node)
            undo_redo_manager.add_do_method(tree_node, "set_owner", root)
            undo_redo_manager.add_do_reference(tree_node)
            undo_redo_manager.add_undo_method(root, "remove_child", tree_node)
            undo_redo_manager.commit_action()
        else:
            root.add_child(tree_node)
            tree_node.owner = root
    elif not (tree_node is AnimationTree):
        return {"status": "error", "error": "Target node is not an AnimationTree: " + anim_tree_path}

    var anim_tree = tree_node as AnimationTree
    anim_tree.anim_player = NodePath(anim_player_path)
    anim_tree.active = active

    var tree_type_str = String(tree_type).to_lower()
    if tree_type_str == "state_machine" or tree_type_str == "animationnodestatemachine":
        var state_machine = AnimationNodeStateMachine.new()
        var states = params.get("states", [])
        for s in states:
            var s_name = ""
            var anim_name = ""
            if typeof(s) == TYPE_STRING:
                s_name = s
                anim_name = s
            elif typeof(s) == TYPE_DICTIONARY:
                s_name = s.get("name", "")
                anim_name = s.get("animation", s_name)
            if s_name != "":
                var anim_node = AnimationNodeAnimation.new()
                anim_node.animation = anim_name
                state_machine.add_node(s_name, anim_node)

        var transitions = params.get("transitions", [])
        for t in transitions:
            if typeof(t) == TYPE_DICTIONARY:
                var from_n = t.get("from", "")
                var to_n = t.get("to", "")
                if from_n != "" and to_n != "":
                    var trans = AnimationNodeStateMachineTransition.new()
                    if t.has("switch_mode"):
                        trans.switch_mode = int(t["switch_mode"])
                    if t.has("advance_mode"):
                        trans.advance_mode = int(t["advance_mode"])
                    elif t.get("auto_advance", false):
                        trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
                    state_machine.add_transition(from_n, to_n, trans)

        var start_node = params.get("start_node", "")
        if start_node != "":
            var start_trans = AnimationNodeStateMachineTransition.new()
            start_trans.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
            state_machine.add_transition("Start", start_node, start_trans)

        anim_tree.tree_root = state_machine

    elif tree_type_str == "blend_tree" or tree_type_str == "animationnodeblendtree":
        var blend_tree = AnimationNodeBlendTree.new()
        var blend_nodes = params.get("blend_nodes", [])
        for bn in blend_nodes:
            if typeof(bn) == TYPE_DICTIONARY:
                var b_name = bn.get("name", "")
                var b_type = bn.get("type", "AnimationNodeAnimation")
                var anim_name = bn.get("animation", "")
                if b_name != "" and ClassDB.class_exists(b_type):
                    var node_inst = ClassDB.instantiate(b_type)
                    if node_inst is AnimationNodeAnimation and anim_name != "":
                        node_inst.animation = anim_name
                    blend_tree.add_node(b_name, node_inst)

        var connections = params.get("connections", [])
        for conn in connections:
            if typeof(conn) == TYPE_DICTIONARY:
                var from_node = conn.get("from_node", "")
                var to_node = conn.get("to_node", "output")
                var to_input = conn.get("to_input", 0)
                if from_node != "" and to_node != "":
                    blend_tree.connect_node(to_node, to_input, from_node)

        anim_tree.tree_root = blend_tree

    elif tree_type_str == "blend_space_2d" or tree_type_str == "animationnodeblendspace2d":
        anim_tree.tree_root = AnimationNodeBlendSpace2D.new()

    elif tree_type_str == "blend_space_1d" or tree_type_str == "animationnodeblendspace1d":
        anim_tree.tree_root = AnimationNodeBlendSpace1D.new()

    return {
        "status": "ok",
        "result": {
            "animation_tree_path": String(anim_tree.get_path()),
            "anim_player": String(anim_tree.anim_player),
            "tree_type": tree_type,
            "active": anim_tree.active
        }
    }

func parse_variant(val):
    if typeof(val) == TYPE_STRING:
        var s_val = String(val).strip_edges()
        if s_val.to_lower() == "true": return true
        if s_val.to_lower() == "false": return false
        if s_val.begins_with("Vector") or s_val.begins_with("Color") or s_val.begins_with("Rect") or s_val.begins_with("Transform") or s_val.begins_with("Basis") or s_val.begins_with("Quaternion") or s_val.begins_with("[") or s_val.begins_with("{"):
            var parsed_str = str_to_var(s_val)
            if parsed_str != null:
                return parsed_str
        return val

    if typeof(val) == TYPE_ARRAY:
        var res_arr = []
        for elem in val:
            res_arr.append(parse_variant(elem))
        return res_arr

    if typeof(val) == TYPE_DICTIONARY:
        if val.has("__type"):
            var t = val["__type"]
            match t:
                "Vector2": return Vector2(float(val.get("x", 0)), float(val.get("y", 0)))
                "Vector2i": return Vector2i(int(val.get("x", 0)), int(val.get("y", 0)))
                "Vector3": return Vector3(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("z", 0)))
                "Vector3i": return Vector3i(int(val.get("x", 0)), int(val.get("y", 0)), int(val.get("z", 0)))
                "Vector4": return Vector4(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("z", 0)), float(val.get("w", 0)))
                "Quaternion": return Quaternion(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("z", 0)), float(val.get("w", 1)))
                "Color": return Color(float(val.get("r", 0)), float(val.get("g", 0)), float(val.get("b", 0)), float(val.get("a", 1)))
                "Rect2": return Rect2(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("width", val.get("w", 0))), float(val.get("height", val.get("h", 0))))
                "Rect2i": return Rect2i(int(val.get("x", 0)), int(val.get("y", 0)), int(val.get("width", val.get("w", 0))), int(val.get("height", val.get("h", 0))))
                "Transform2D":
                    var xv = parse_variant(val.get("x", {"x": 1, "y": 0}))
                    var yv = parse_variant(val.get("y", {"x": 0, "y": 1}))
                    var ov = parse_variant(val.get("origin", {"x": 0, "y": 0}))
                    return Transform2D(xv, yv, ov)
                "Transform3D":
                    var bv = parse_variant(val.get("basis", {}))
                    var ov = parse_variant(val.get("origin", {"x": 0, "y": 0, "z": 0}))
                    var b_inst = bv if typeof(bv) == TYPE_BASIS else Basis()
                    return Transform3D(b_inst, ov)
                "Basis":
                    if val.has("x") and val.has("y") and val.has("z"):
                        return Basis(parse_variant(val["x"]), parse_variant(val["y"]), parse_variant(val["z"]))
                    return Basis()
        elif val.has("x") and val.has("y") and val.has("z") and val.has("w"):
            return Quaternion(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("z", 0)), float(val.get("w", 1)))
        elif val.has("x") and val.has("y") and val.has("z"):
            return Vector3(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("z", 0)))
        elif val.has("x") and val.has("y"):
            return Vector2(float(val.get("x", 0)), float(val.get("y", 0)))
        elif val.has("r") and val.has("g") and val.has("b"):
            return Color(float(val.get("r", 0)), float(val.get("g", 0)), float(val.get("b", 0)), float(val.get("a", 1)))

        var res_dict = {}
        for k in val:
            res_dict[k] = parse_variant(val[k])
        return res_dict

    return val

func get_uid_in_editor(params: Dictionary) -> Dictionary:
    var file_path = params.get("file_path", "")
    if file_path == "":
        return {"status": "error", "error": "Missing file_path parameter"}
    var uid_int = ResourceLoader.get_resource_uid(file_path)
    var uid_text = ""
    if uid_int != -1 and ClassDB.class_exists("ResourceUID"):
        uid_text = ResourceUID.id_to_text(uid_int)
    elif uid_int != -1:
        uid_text = "uid://" + String.num_int64(uid_int, 36)
    return {
        "status": "ok",
        "result": {
            "uid": uid_int,
            "uid_text": uid_text,
            "file_path": file_path
        }
    }

func update_project_uids_in_editor(params: Dictionary) -> Dictionary:
    var project_path = params.get("project_path", ".")
    if editor_interface:
        var fs = editor_interface.get_resource_filesystem()
        if fs:
            fs.scan()
            return {
                "status": "ok",
                "result": {
                    "project_path": project_path,
                    "message": "Resource filesystem scanned and project UIDs updated in editor"
                }
            }
    return {"status": "ok", "result": {"project_path": project_path, "message": "Project UIDs synchronized"}}

func export_mesh_library_in_editor(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var output_path = params.get("output_path", "")
    var generate_collisions = params.get("generate_collisions", false)

    var root: Node = null
    if scene_path != "" and FileAccess.file_exists(scene_path):
        var packed = ResourceLoader.load(scene_path) as PackedScene
        if packed:
            root = packed.instantiate()
    elif editor_interface:
        root = editor_interface.get_edited_scene_root()

    if not root:
        return {"status": "error", "error": "No valid scene found for export"}
    if output_path == "":
        return {"status": "error", "error": "Missing output_path"}

    var mesh_lib = MeshLibrary.new()
    var item_id = 0

    for child in root.get_children():
        if child is MeshInstance3D and child.mesh:
            mesh_lib.create_item(item_id)
            mesh_lib.set_item_name(item_id, child.name)
            mesh_lib.set_item_mesh(item_id, child.mesh)

            var shapes = []
            for sub in child.get_children():
                if sub is CollisionShape3D and sub.shape:
                    shapes.append(sub.shape)
                    shapes.append(sub.transform)

            if shapes.is_empty() and generate_collisions:
                var col_shape = child.mesh.create_trimesh_shape()
                if col_shape:
                    shapes.append(col_shape)
                    shapes.append(Transform3D.IDENTITY)

            if not shapes.is_empty():
                mesh_lib.set_item_shapes(item_id, shapes)

            item_id += 1

    var err = ResourceSaver.save(mesh_lib, output_path)
    if err != OK:
        return {"status": "error", "error": "Failed to save MeshLibrary to '%s': %d" % [output_path, err]}

    if editor_interface:
        editor_interface.get_resource_filesystem().scan()

    return {
        "status": "ok",
        "result": {
            "items_exported": item_id,
            "output_path": output_path,
            "generate_collisions": generate_collisions
        }
    }

func install_editor_plugin_in_editor(params: Dictionary) -> Dictionary:
    var project_path = params.get("project_path", ".")
    var plugin_path = "res://addons/godot_mcp/plugin.cfg"
    if editor_interface:
        editor_interface.set_plugin_enabled("godot_mcp", true)
    return {"status": "ok", "result": {"installed": true, "plugin": plugin_path, "project_path": project_path}}

func process_and_encode_image(img: Image, params: Dictionary) -> Dictionary:
    var format_str = String(params.get("format", "png")).to_lower()
    var max_width = int(params.get("max_width", 0))
    var max_height = int(params.get("max_height", 0))
    var raw_quality = params.get("quality", 0.75)

    var quality = float(raw_quality)
    if quality > 1.0:
        quality = quality / 100.0
    quality = clampf(quality, 0.0, 1.0)

    var orig_w = img.get_width()
    var orig_h = img.get_height()
    var new_w = orig_w
    var new_h = orig_h

    if max_width > 0 and new_w > max_width:
        var scale = float(max_width) / float(new_w)
        new_w = max_width
        new_h = int(new_h * scale)

    if max_height > 0 and new_h > max_height:
        var scale = float(max_height) / float(new_h)
        new_h = max_height
        new_w = int(new_h * scale)

    if new_w != orig_w or new_h != orig_h:
        img.resize(new_w, new_h, Image.INTERPOLATE_LANCZOS)

    var buffer: PackedByteArray
    var mime_type = "image/png"

    if format_str == "jpg" or format_str == "jpeg":
        buffer = img.save_jpg_to_buffer(quality)
        mime_type = "image/jpeg"
    else:
        buffer = img.save_png_to_buffer()
        mime_type = "image/png"

    var b64 = Marshalls.raw_to_base64(buffer)
    return {
        "status": "ok",
        "result": {
            "image_base64": b64,
            "mime_type": mime_type,
            "width": img.get_width(),
            "height": img.get_height(),
            "format": format_str
        }
    }

func parse_key_code(val) -> Key:
    if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
        return int(val) as Key
    var s = String(val)
    if s.is_valid_int():
        return int(s) as Key
    if s.begins_with("KEY_"):
        s = s.substr(4)
    var kc = OS.find_keycode_from_string(s)
    if kc != KEY_NONE:
        return kc
    return KEY_NONE

func import_asset_in_editor(params: Dictionary) -> Dictionary:
    var asset_path = String(params.get("asset_path", params.get("path", params.get("file_path", ""))))
    if asset_path == "":
        return {"status": "error", "error": "Missing asset_path parameter"}

    if not asset_path.begins_with("res://") and not asset_path.begins_with("/"):
        if FileAccess.file_exists("res://" + asset_path):
            asset_path = "res://" + asset_path

    if not FileAccess.file_exists(asset_path):
        return {"status": "error", "error": "Asset file not found at: " + asset_path}

    var import_file_path = asset_path + ".import"
    var config = ConfigFile.new()
    var file_existed = FileAccess.file_exists(import_file_path)

    if file_existed:
        var load_err = config.load(import_file_path)
        if load_err != OK:
            return {"status": "error", "error": "Failed to load .import file at '%s': %d" % [import_file_path, load_err]}

    var ext = asset_path.get_extension().to_lower()
    var default_importer = ""
    var default_type = ""

    if ext in ["gltf", "glb", "obj", "fbx", "blend"]:
        default_importer = "scene"
        default_type = "PackedScene"
    elif ext in ["png", "jpg", "jpeg", "webp", "tga", "bmp", "svg"]:
        default_importer = "texture"
        default_type = "CompressedTexture2D"
    elif ext == "wav":
        default_importer = "wav"
        default_type = "AudioStreamWAV"
    elif ext == "ogg":
        default_importer = "oggvorbis"
        default_type = "AudioStreamOggVorbis"

    if not config.has_section("remap"):
        if default_importer != "":
            config.set_value("remap", "importer", default_importer)
            config.set_value("remap", "importer_version", 1)
            config.set_value("remap", "type", default_type)
        else:
            config.set_value("remap", "importer", "keep")

    if not config.has_section("deps"):
        config.set_value("deps", "source_file", asset_path)

    var current_importer = String(config.get_value("remap", "importer", default_importer))

    # 1. Collision generation mode (3D models)
    if params.has("collision_mode") or params.has("collision_generation_mode") or params.has("generate_collisions") or params.has("physics_import_mesh_has_collision"):
        var col_val = params.get("collision_mode", params.get("collision_generation_mode", params.get("generate_collisions", params.get("physics_import_mesh_has_collision"))))
        if typeof(col_val) == TYPE_BOOL:
            config.set_value("params", "physics/import_mesh_has_collision", col_val)
        else:
            var c_str = String(col_val).to_lower()
            if c_str in ["true", "trimesh", "convex", "static", "multiple", "1"]:
                config.set_value("params", "physics/import_mesh_has_collision", true)
            elif c_str in ["false", "none", "off", "0"]:
                config.set_value("params", "physics/import_mesh_has_collision", false)

    # 2. Scale (3D models)
    if params.has("scale"):
        var s_val = float(params["scale"])
        config.set_value("params", "nodes/root_scale", s_val)
        config.set_value("params", "nodes/scale_mesh", s_val)
    if params.has("root_scale"):
        config.set_value("params", "nodes/root_scale", float(params["root_scale"]))
    if params.has("scale_mesh"):
        config.set_value("params", "nodes/scale_mesh", float(params["scale_mesh"]))

    # 3. Animation loop & loop mode (3D models, audio)
    if params.has("animation_loop") or params.has("loop") or params.has("loop_mode"):
        var has_loop_flag = params.has("animation_loop") or params.has("loop")
        var loop_flag = params.get("animation_loop", params.get("loop", false))

        if current_importer == "scene" or ext in ["gltf", "glb", "obj", "fbx", "blend"]:
            config.set_value("params", "animation/import", true)
            if has_loop_flag:
                config.set_value("params", "animation/loop_mode", 1 if loop_flag else 0)
            if params.has("loop_mode"):
                var lm = String(params["loop_mode"]).to_lower()
                if lm in ["none", "disabled", "off", "0"]:
                    config.set_value("params", "animation/loop_mode", 0)
                elif lm in ["linear", "loop", "forward", "1"]:
                    config.set_value("params", "animation/loop_mode", 1)
                elif lm in ["pingpong", "2"]:
                    config.set_value("params", "animation/loop_mode", 2)
                elif lm.is_valid_int():
                    config.set_value("params", "animation/loop_mode", int(lm))
        elif current_importer == "wav" or ext == "wav":
            if has_loop_flag:
                config.set_value("params", "edit/loop_mode", 1 if loop_flag else 0)
            if params.has("loop_mode"):
                var lm = String(params["loop_mode"]).to_lower()
                if lm in ["disabled", "none", "off", "0"]:
                    config.set_value("params", "edit/loop_mode", 0)
                elif lm in ["forward", "linear", "loop", "1"]:
                    config.set_value("params", "edit/loop_mode", 1)
                elif lm in ["pingpong", "2"]:
                    config.set_value("params", "edit/loop_mode", 2)
                elif lm in ["backward", "3"]:
                    config.set_value("params", "edit/loop_mode", 3)
                elif lm.is_valid_int():
                    config.set_value("params", "edit/loop_mode", int(lm))
        elif current_importer == "oggvorbis" or ext == "ogg":
            if has_loop_flag:
                config.set_value("params", "loop", loop_flag)
            if params.has("loop_mode"):
                var lm = String(params["loop_mode"]).to_lower()
                config.set_value("params", "loop", lm not in ["none", "disabled", "off", "0"])

    # 4. Compressed VRAM formats (Textures)
    if params.has("compressed_vram") or params.has("vram_compression") or params.has("vram_texture_compression") or params.has("compress_mode"):
        if current_importer == "texture" or ext in ["png", "jpg", "jpeg", "webp", "tga", "bmp", "svg"]:
            if params.has("compress_mode"):
                var cm_val = params["compress_mode"]
                if typeof(cm_val) == TYPE_INT or typeof(cm_val) == TYPE_FLOAT:
                    config.set_value("params", "compress/mode", int(cm_val))
                else:
                    var cm = String(cm_val).to_lower()
                    if cm in ["lossless", "0"]:
                        config.set_value("params", "compress/mode", 0)
                    elif cm in ["lossy", "1"]:
                        config.set_value("params", "compress/mode", 1)
                    elif cm in ["vram_compressed", "vram", "compressed", "2"]:
                        config.set_value("params", "compress/mode", 2)
                    elif cm in ["vram_uncompressed", "uncompressed", "3"]:
                        config.set_value("params", "compress/mode", 3)
                    elif cm in ["basis_universal", "basis", "4"]:
                        config.set_value("params", "compress/mode", 4)
            else:
                var vram_flag = params.get("compressed_vram", params.get("vram_compression", params.get("vram_texture_compression", false)))
                if vram_flag:
                    config.set_value("params", "compress/mode", 2)

    if params.has("high_quality"):
        config.set_value("params", "compress/high_quality", bool(params["high_quality"]))

    # 5. Direct custom import settings
    var custom_settings = params.get("import_settings", params.get("custom_settings", params.get("settings", {})))
    if typeof(custom_settings) == TYPE_DICTIONARY:
        for k in custom_settings:
            config.set_value("params", String(k), parse_variant(custom_settings[k]))

    for k in params:
        if "/" in String(k):
            config.set_value("params", String(k), parse_variant(params[k]))

    var save_err = config.save(import_file_path)
    if save_err != OK:
        return {"status": "error", "error": "Failed to save .import file at '%s': %d" % [import_file_path, save_err]}

    var reimported = false
    if editor_interface:
        var efs = editor_interface.get_resource_filesystem()
        if efs:
            efs.reimport_files(PackedStringArray([asset_path]))
            reimported = true

    var updated_params = {}
    if config.has_section("params"):
        for k in config.get_section_keys("params"):
            updated_params[k] = config.get_value("params", k)

    return {
        "status": "ok",
        "result": {
            "asset_path": asset_path,
            "import_file": import_file_path,
            "reimported": reimported,
            "import_settings": updated_params
        }
    }

func get_performance_metrics_in_editor(params: Dictionary = {}) -> Dictionary:
    var metrics = {
        "time_fps": Performance.get_monitor(Performance.TIME_FPS),
        "time_process": Performance.get_monitor(Performance.TIME_PROCESS),
        "time_physics_process": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
        "memory_static": Performance.get_monitor(Performance.MEMORY_STATIC),
        "memory_static_max": Performance.get_monitor(Performance.MEMORY_STATIC_MAX),
        "memory_message_buffer_max": Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX),
        "object_node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
        "object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
        "object_resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
        "render_total_draw_calls_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
        "render_total_objects_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
        "render_video_mem_used": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
        "physics_2d_active_objects": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
        "physics_2d_collision_pairs": Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
        "physics_3d_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
        "physics_3d_collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
    }
    return {"status": "ok", "result": metrics}

func get_memory_breakdown_in_editor(params: Dictionary = {}) -> Dictionary:
    var mem_static = Performance.get_monitor(Performance.MEMORY_STATIC)
    var mem_static_max = Performance.get_monitor(Performance.MEMORY_STATIC_MAX)
    var mem_msg_buf_max = Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX)

    var vram_total = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
    var vram_texture = 0
    if Performance.get("RENDER_TEXTURE_MEM_USED") != null:
        vram_texture = Performance.get_monitor(Performance.get("RENDER_TEXTURE_MEM_USED"))
    var vram_buffer = 0
    if Performance.get("RENDER_BUFFER_MEM_USED") != null:
        vram_buffer = Performance.get_monitor(Performance.get("RENDER_BUFFER_MEM_USED"))

    var count_objects = Performance.get_monitor(Performance.OBJECT_COUNT)
    var count_nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
    var count_resources = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
    var count_orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

    var breakdown = {
        "static_memory": {
            "current_bytes": mem_static,
            "peak_bytes": mem_static_max,
            "message_buffer_max_bytes": mem_msg_buf_max
        },
        "video_memory": {
            "total_video_mem_bytes": vram_total,
            "texture_mem_bytes": vram_texture,
            "buffer_mem_bytes": vram_buffer
        },
        "object_allocations": {
            "object_count": count_objects,
            "node_count": count_nodes,
            "resource_count": count_resources,
            "orphan_node_count": count_orphans
        },
        "summary": {
            "total_static_mb": float(mem_static) / (1024.0 * 1024.0),
            "peak_static_mb": float(mem_static_max) / (1024.0 * 1024.0),
            "total_video_mb": float(vram_total) / (1024.0 * 1024.0),
            "total_objects": count_objects,
            "total_nodes": count_nodes,
            "total_resources": count_resources
        }
    }
    return {"status": "ok", "result": breakdown}

func create_behavior_tree_in_editor(params: Dictionary) -> Dictionary:
    var scene_path = String(params.get("scene_path", ""))
    var parent_path = String(params.get("parent_path", "."))
    var root_type = String(params.get("root_type", params.get("type", "Node")))
    var root_name = String(params.get("root_name", params.get("name", "BehaviorTree")))
    var nodes = params.get("nodes", [])
    var tree_type = String(params.get("tree_type", "standard"))

    var root: Node = editor_interface.get_edited_scene_root() if editor_interface else null
    var created_root_scene = false

    if not root:
        if scene_path != "" and FileAccess.file_exists(scene_path):
            var ps = ResourceLoader.load(scene_path) as PackedScene
            if ps:
                root = ps.instantiate()
        else:
            var base_type = root_type
            if not ClassDB.class_exists(base_type):
                base_type = "Node"
            root = ClassDB.instantiate(base_type) as Node
            root.name = root_name
            created_root_scene = true

    var parent_node: Node = root
    var bt_root_node: Node = null

    if created_root_scene:
        bt_root_node = root
    else:
        if parent_path != "." and parent_path != "":
            parent_node = root.get_node_or_null(parent_path)
            if not parent_node:
                return {"status": "error", "error": "Parent node not found: " + parent_path}

        var bt_type = root_type
        if not ClassDB.class_exists(bt_type):
            bt_type = "Node"
        bt_root_node = ClassDB.instantiate(bt_type) as Node
        bt_root_node.name = root_name

        if undo_redo_manager:
            undo_redo_manager.create_action("Create BehaviorTree Root " + root_name)
            undo_redo_manager.add_do_method(parent_node, "add_child", bt_root_node)
            undo_redo_manager.add_do_method(bt_root_node, "set_owner", root)
            undo_redo_manager.add_do_reference(bt_root_node)
            undo_redo_manager.add_undo_method(parent_node, "remove_child", bt_root_node)
            undo_redo_manager.commit_action()
        else:
            parent_node.add_child(bt_root_node)
            bt_root_node.owner = root

    var created_info = []
    if typeof(nodes) == TYPE_ARRAY:
        for n_def in nodes:
            if typeof(n_def) == TYPE_DICTIONARY:
                var child_info = _build_bt_node_in_editor(bt_root_node, n_def, root, tree_type)
                created_info.append(child_info)

    if scene_path != "":
        var packed = PackedScene.new()
        if packed.pack(root) == OK:
            ResourceSaver.save(packed, scene_path)

    if editor_interface:
        editor_interface.get_resource_filesystem().scan()

    return {
        "status": "ok",
        "result": {
            "root_name": bt_root_node.name,
            "root_type": bt_root_node.get_class(),
            "tree_type": tree_type,
            "scene_path": scene_path,
            "nodes_created": created_info
        }
    }

func _build_bt_node_in_editor(parent_node: Node, node_def: Dictionary, scene_root: Node, tree_type: String = "standard") -> Dictionary:
    var name = String(node_def.get("name", "BTNode"))
    var raw_type = String(node_def.get("type", "Node"))
    var script_path = String(node_def.get("script_path", ""))
    var script_content = String(node_def.get("script_content", ""))
    var props = node_def.get("properties", {})

    var resolved_type = raw_type
    if not ClassDB.class_exists(resolved_type):
        match raw_type.to_lower():
            "sequence":
                resolved_type = "BTSequence" if ClassDB.class_exists("BTSequence") else "Node"
            "selector":
                resolved_type = "BTSelector" if ClassDB.class_exists("BTSelector") else "Node"
            "inverter":
                resolved_type = "BTInverter" if ClassDB.class_exists("BTInverter") else "Node"
            "action":
                resolved_type = "BTAction" if ClassDB.class_exists("BTAction") else "Node"
            "condition":
                resolved_type = "BTCondition" if ClassDB.class_exists("BTCondition") else "Node"
            _:
                resolved_type = "Node"

    var node = ClassDB.instantiate(resolved_type) as Node
    node.name = name

    if script_path != "":
        if script_content != "":
            var dir_path = script_path.get_base_dir()
            if not DirAccess.dir_exists_absolute(dir_path):
                DirAccess.make_dir_recursive_absolute(dir_path)
            var f = FileAccess.open(script_path, FileAccess.WRITE)
            if f:
                f.store_string(script_content)
                f.close()
        elif not FileAccess.file_exists(script_path):
            var default_code = _generate_default_bt_script(raw_type, script_path)
            var dir_path = script_path.get_base_dir()
            if not DirAccess.dir_exists_absolute(dir_path):
                DirAccess.make_dir_recursive_absolute(dir_path)
            var f = FileAccess.open(script_path, FileAccess.WRITE)
            if f:
                f.store_string(default_code)
                f.close()

        if FileAccess.file_exists(script_path):
            var scr = ResourceLoader.load(script_path) as Script
            if scr:
                node.set_script(scr)

    if typeof(props) == TYPE_DICTIONARY:
        for k in props:
            node.set(k, parse_variant(props[k]))

    if undo_redo_manager:
        undo_redo_manager.create_action("Add BT Node " + name)
        undo_redo_manager.add_do_method(parent_node, "add_child", node)
        undo_redo_manager.add_do_method(node, "set_owner", scene_root)
        undo_redo_manager.add_do_reference(node)
        undo_redo_manager.add_undo_method(parent_node, "remove_child", node)
        undo_redo_manager.commit_action()
    else:
        parent_node.add_child(node)
        if scene_root:
            node.owner = scene_root

    var children_info = []
    var children_defs = node_def.get("children", [])
    if typeof(children_defs) == TYPE_ARRAY:
        for c_def in children_defs:
            if typeof(c_def) == TYPE_DICTIONARY:
                children_info.append(_build_bt_node_in_editor(node, c_def, scene_root, tree_type))

    return {
        "name": node.name,
        "type": node.get_class(),
        "path": String(node.get_path()) if node.is_inside_tree() else node.name,
        "script": script_path,
        "children": children_info
    }

func _generate_default_bt_script(node_type: String, _script_path: String) -> String:
    var t = node_type.to_lower()
    if "condition" in t:
        if ClassDB.class_exists("BTCondition"):
            return "extends BTCondition\n\n# LimboAI / BT Condition Script\nfunc _tick(delta: float) -> Status:\n\treturn Status.SUCCESS\n"
        else:
            return "extends Node\n\n# BT Condition Script\n@export var blackboard: Node\n\nfunc check_condition() -> bool:\n\treturn true\n"
    elif "action" in t:
        if ClassDB.class_exists("BTAction"):
            return "extends BTAction\n\n# LimboAI / BT Action Script\nfunc _tick(delta: float) -> Status:\n\treturn Status.SUCCESS\n"
        else:
            return "extends Node\n\n# BT Action Script\n@export var blackboard: Node\n\nfunc execute(delta: float) -> int:\n\treturn 1 # 0: FAILURE, 1: SUCCESS, 2: RUNNING\n"
    else:
        return "extends Node\n\n# Behavior Tree Task Script\nfunc _ready():\n\tpass\n"

func configure_blackboard_in_editor(params: Dictionary) -> Dictionary:
    var scene_path = String(params.get("scene_path", ""))
    var node_path = String(params.get("node_path", params.get("parent_path", ".")))
    var variables = params.get("variables", params.get("blackboard_data", params.get("parameters", {})))
    var bb_name = String(params.get("blackboard_name", "Blackboard"))
    var create_component = bool(params.get("create_component", true))
    var script_path = String(params.get("script_path", ""))
    var export_as_script = bool(params.get("export_as_script", script_path != ""))
    var override_existing = bool(params.get("override_existing", true))

    if typeof(variables) != TYPE_DICTIONARY:
        variables = {}

    var parsed_vars = {}
    for k in variables:
        parsed_vars[k] = parse_variant(variables[k])

    var scene_root: Node = editor_interface.get_edited_scene_root() if editor_interface else null
    if not scene_root and scene_path != "" and FileAccess.file_exists(scene_path):
        var ps = ResourceLoader.load(scene_path) as PackedScene
        if ps:
            scene_root = ps.instantiate()

    var target_node: Node = null
    if scene_root:
        target_node = scene_root if node_path == "." else scene_root.get_node_or_null(node_path)

    if not target_node:
        if scene_root and create_component:
            target_node = Node.new()
            target_node.name = bb_name
            if undo_redo_manager:
                undo_redo_manager.create_action("Add Blackboard Node " + bb_name)
                undo_redo_manager.add_do_method(scene_root, "add_child", target_node)
                undo_redo_manager.add_do_method(target_node, "set_owner", scene_root)
                undo_redo_manager.add_do_reference(target_node)
                undo_redo_manager.add_undo_method(scene_root, "remove_child", target_node)
                undo_redo_manager.commit_action()
            else:
                scene_root.add_child(target_node)
                target_node.owner = scene_root
        elif not scene_root:
            target_node = Node.new()
            target_node.name = bb_name
            scene_root = target_node

    if script_path != "" or export_as_script:
        if script_path == "":
            script_path = "res://scripts/blackboard.gd"
        var dir_path = script_path.get_base_dir()
        if not DirAccess.dir_exists_absolute(dir_path):
            DirAccess.make_dir_recursive_absolute(dir_path)

        var script_code = _generate_blackboard_script(parsed_vars)
        var f = FileAccess.open(script_path, FileAccess.WRITE)
        if f:
            f.store_string(script_code)
            f.close()

        if FileAccess.file_exists(script_path):
            var scr = ResourceLoader.load(script_path) as Script
            if scr:
                target_node.set_script(scr)

    var current_vars = target_node.get_meta("blackboard", {})
    if typeof(current_vars) != TYPE_DICTIONARY:
        current_vars = {}

    if override_existing:
        current_vars = parsed_vars.duplicate()
    else:
        for k in parsed_vars:
            current_vars[k] = parsed_vars[k]

    target_node.set_meta("blackboard", current_vars)

    for k in parsed_vars:
        if k in target_node:
            target_node.set(k, parsed_vars[k])

    if scene_path != "" and scene_root:
        var packed = PackedScene.new()
        if packed.pack(scene_root) == OK:
            ResourceSaver.save(packed, scene_path)

    if editor_interface:
        editor_interface.get_resource_filesystem().scan()

    return {
        "status": "ok",
        "result": {
            "node_path": String(target_node.get_path()) if target_node.is_inside_tree() else target_node.name,
            "variables": current_vars,
            "scene_path": scene_path,
            "script_path": script_path if (script_path != "" or export_as_script) else ""
        }
    }

func _generate_blackboard_script(variables: Dictionary) -> String:
    var var_str = JSON.stringify(variables, "    ")
    return "extends Node\nclass_name Blackboard\n\nsignal variable_changed(key: String, value: Variant)\n\n@export var data: Dictionary = %s\n\nfunc set_var(key: String, value: Variant) -> void:\n\tdata[key] = value\n\tvariable_changed.emit(key, value)\n\nfunc get_var(key: String, default_value: Variant = null) -> Variant:\n\treturn data.get(key, default_value)\n\nfunc has_var(key: String) -> bool:\n\treturn data.has(key)\n" % var_str





func execute_gdscript_in_editor(params: Dictionary) -> Dictionary:
    var code: String = String(params.get("code", params.get("script_code", params.get("script", ""))))
    if code.strip_edges() == "":
        return {"status": "error", "error": "No GDScript code provided."}
    
    var script = GDScript.new()
    var lines = code.split("\n")
    var has_func = false
    for l in lines:
        if l.strip_edges().begins_with("func "):
            has_func = true
            break
            
    if has_func:
        script.source_code = "@tool\nextends RefCounted\n\n" + code
    else:
        script.source_code = "@tool\nextends RefCounted\n\nfunc eval():\n"
        for line in lines:
            script.source_code += "\t" + line + "\n"
            
    var err = script.reload()
    if err != OK:
        return {"status": "error", "error": "Failed to compile GDScript code (Error %d)." % err}
    
    var obj = RefCounted.new()
    obj.set_script(script)
    var func_to_call = "eval"
    if not obj.has_method("eval") and has_func:
        for l in lines:
            var cl = l.strip_edges()
            if cl.begins_with("func "):
                func_to_call = cl.substr(5).split("(")[0].strip_edges()
                break
                
    var result = obj.call(func_to_call)
    return {"status": "ok", "result": result}

func read_resource_in_editor(params: Dictionary) -> Dictionary:
    var res_path = params.get("resource_path", "")
    if not FileAccess.file_exists(res_path):
        return {"status": "error", "error": "Resource not found: " + res_path}
    var res = ResourceLoader.load(res_path)
    if not res:
        return {"status": "error", "error": "Failed to load resource"}
    var props = {}
    for p in res.get_property_list():
        var name = p["name"]
        props[name] = str(res.get(name))
    return {"status": "ok", "result": props}

func modify_resource_in_editor(params: Dictionary) -> Dictionary:
    var res_path = params.get("resource_path", "")
    var props = params.get("properties", {})
    if not FileAccess.file_exists(res_path):
        return {"status": "error", "error": "Resource not found: " + res_path}
    var res = ResourceLoader.load(res_path)
    if not res:
        return {"status": "error", "error": "Failed to load resource"}
    for k in props:
        res.set(k, parse_variant(props[k]))
    ResourceSaver.save(res, res_path)
    if editor_interface:
        editor_interface.get_resource_filesystem().scan()
    return {"status": "ok", "result": "Resource updated"}

func get_editor_selection_in_editor(_params: Dictionary) -> Dictionary:
    if not editor_interface:
        return {"status": "error", "error": "EditorInterface not available"}
    var sel = editor_interface.get_selection().get_selected_nodes()
    var result = []
    for n in sel:
        result.append({
            "name": n.name,
            "class": n.get_class(),
            "path": String(n.get_path())
        })
    return {"status": "ok", "result": result}

func set_editor_selection_in_editor(params: Dictionary) -> Dictionary:
    if not editor_interface:
        return {"status": "error", "error": "EditorInterface not available"}
    var root = editor_interface.get_edited_scene_root()
    if not root:
        return {"status": "error", "error": "No active scene open in editor"}
    var paths = params.get("nodes", params.get("paths", []))
    if typeof(paths) == TYPE_STRING:
        paths = [paths]
    
    var sel = editor_interface.get_selection()
    sel.clear()
    var selected_count = 0
    for p in paths:
        var target = root if (p == "." or p == "" or p == root.name) else root.get_node_or_null(p)
        if target:
            sel.add_node(target)
            editor_interface.edit_node(target)
            selected_count += 1
            
    return {"status": "ok", "result": {"selected_count": selected_count}}

func focus_editor_viewport_3d_in_editor(params: Dictionary) -> Dictionary:
    if not editor_interface:
        return {"status": "error", "error": "EditorInterface not available"}
    var root = editor_interface.get_edited_scene_root()
    var node_path = params.get("node_path", params.get("target", "."))
    var target: Node = root if (node_path == "." or node_path == "" or (root and node_path == root.name)) else (root.get_node_or_null(node_path) if root else null)
    
    if target:
        editor_interface.get_selection().clear()
        editor_interface.get_selection().add_node(target)
        editor_interface.edit_node(target)
        if target is Node3D:
            return {"status": "ok", "result": {"focused_node": target.name, "global_position": str(target.global_position)}}
        return {"status": "ok", "result": {"focused_node": target.name}}
    
    return {"status": "ok", "result": "Focused 3D editor viewport"}

func get_active_script_editor_in_editor(_params: Dictionary) -> Dictionary:
    if not editor_interface:
        return {"status": "error", "error": "EditorInterface not available"}
    var script_editor = editor_interface.get_script_editor()
    if not script_editor:
        return {"status": "error", "error": "ScriptEditor not active"}
    var cur_script = script_editor.get_current_script()
    if not cur_script:
        return {"status": "ok", "result": {"active_script": null, "open_scripts": []}}
    
    var open_list = []
    for s in script_editor.get_open_scripts():
        open_list.append(s.resource_path)
        
    return {
        "status": "ok",
        "result": {
            "active_script": cur_script.resource_path,
            "open_scripts": open_list
        }
    }

func get_debugger_errors_in_editor(params: Dictionary) -> Dictionary:
    if not debugger_plugin:
        return {"status": "ok", "result": [], "counts": {}}
    var filter = {}
    if params.has("type"):
        filter["type"] = params["type"]
    if params.has("severity"):
        filter["severity"] = params["severity"]
    if params.has("since"):
        filter["since"] = params["since"]
    if params.has("exclude_session_events"):
        filter["exclude_session_events"] = params["exclude_session_events"]
    if debugger_plugin.has_method("get_errors_filtered") and not filter.is_empty():
        var result = debugger_plugin.get_errors_filtered(filter)
        var counts = debugger_plugin.get_error_counts() if debugger_plugin.has_method("get_error_counts") else {}
        return {"status": "ok", "result": result, "counts": counts}
    if debugger_plugin.has_method("get_errors"):
        var result = debugger_plugin.get_errors()
        var counts = debugger_plugin.get_error_counts() if debugger_plugin.has_method("get_error_counts") else {}
        return {"status": "ok", "result": result, "counts": counts}
    return {"status": "ok", "result": [], "counts": {}}

func clear_debugger_errors_in_editor(_params: Dictionary) -> Dictionary:
    if debugger_plugin and debugger_plugin.has_method("clear_errors"):
        debugger_plugin.clear_errors()
        return {"status": "ok", "result": "Errors cleared"}
    return {"status": "ok", "result": "No debugger plugin"}

func get_debugger_error_counts_in_editor(_params: Dictionary) -> Dictionary:
    if debugger_plugin and debugger_plugin.has_method("get_error_counts"):
        var counts = debugger_plugin.get_error_counts()
        var dbg_count = debugger_plugin.get_connected_debugger_count() if debugger_plugin.has_method("get_connected_debugger_count") else 0
        counts["connected_debuggers"] = dbg_count
        return {"status": "ok", "result": counts}
    return {"status": "ok", "result": {}}
