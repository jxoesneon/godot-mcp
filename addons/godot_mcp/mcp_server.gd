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

func parse_variant(val):
    if typeof(val) == TYPE_DICTIONARY:
        if val.has("__type"):
            var t = val["__type"]
            match t:
                "Vector2": return Vector2(float(val.get("x", 0)), float(val.get("y", 0)))
                "Vector2i": return Vector2i(int(val.get("x", 0)), int(val.get("y", 0)))
                "Vector3": return Vector3(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("z", 0)))
                "Vector3i": return Vector3i(int(val.get("x", 0)), int(val.get("y", 0)), int(val.get("z", 0)))
                "Color": return Color(float(val.get("r", 0)), float(val.get("g", 0)), float(val.get("b", 0)), float(val.get("a", 1)))
                "Rect2": return Rect2(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("width", 0)), float(val.get("height", 0)))
        elif val.has("x") and val.has("y") and val.has("z"):
            return Vector3(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("z", 0)))
        elif val.has("x") and val.has("y"):
            return Vector2(float(val.get("x", 0)), float(val.get("y", 0)))
        elif val.has("r") and val.has("g") and val.has("b"):
            return Color(float(val.get("r", 0)), float(val.get("g", 0)), float(val.get("b", 0)), float(val.get("a", 1)))
    return val
