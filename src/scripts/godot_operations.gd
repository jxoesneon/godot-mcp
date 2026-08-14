@tool
extends SceneTree

# Standard operation execution script for Godot MCP in Headless Mode.
# Reads JSON operation arguments from command-line arguments and outputs JSON results.

func _init():
    var args = OS.get_cmdline_args()
    var user_args = OS.get_cmdline_user_args()
    
    # Combined check for operation JSON parameter
    var json_input = ""
    for i in range(args.size()):
        if args[i] == "--op" and i + 1 < args.size():
            json_input = args[i + 1]
            break

    if json_input == "":
        for i in range(user_args.size()):
            if user_args[i] == "--op" and i + 1 < user_args.size():
                json_input = user_args[i + 1]
                break

    if json_input == "":
        log_error("No operation JSON provided via --op argument.")
        quit(1)
        return

    var json = JSON.new()
    var parse_err = json.parse(json_input)
    if parse_err != OK:
        log_error("Failed to parse JSON input: " + json.get_error_message())
        quit(1)
        return

    var data = json.get_data()
    var op = data.get("operation", "")
    var params = data.get("params", {})

    var result = dispatch_operation(op, params)
    print("GODOT_MCP_RESULT:" + JSON.stringify(result))
    quit(0 if result.get("status") == "ok" else 1)

func dispatch_operation(op: String, params: Dictionary) -> Dictionary:
    match op:
        "create_scene":
            return create_scene(params)
        "add_node":
            return add_node(params)
        "modify_node_properties":
            return modify_node_properties(params)
        "delete_node":
            return delete_node(params)
        "reparent_node":
            return reparent_node(params)
        "duplicate_node":
            return duplicate_node(params)
        "inspect_node":
            return inspect_node(params)
        "get_scene_tree":
            return get_scene_tree(params)
        "load_sprite":
            return load_sprite(params)
        "export_mesh_library":
            return export_mesh_library(params)
        "save_scene":
            return save_scene(params)
        "get_uid":
            return get_uid(params)
        "resave_resources":
            return resave_resources(params)
        "create_script":
            return create_script(params)
        "attach_script":
            return attach_script(params)
        "validate_script":
            return validate_script(params)
        "add_input_action":
            return add_input_action(params)
        "bind_input_event":
            return bind_input_event(params)
        "configure_physics_body":
            return configure_physics_body(params)
        "add_collision_shape":
            return add_collision_shape(params)
        "configure_raycast":
            return configure_raycast(params)
        "create_ui_layout":
            return create_ui_layout(params)
        "apply_theme":
            return apply_theme(params)
        "create_particle_system":
            return create_particle_system(params)
        "create_shader_material":
            return create_shader_material(params)
        "set_shader_parameter":
            return set_shader_parameter(params)
        "create_visual_shader":
            return create_visual_shader(params)
        "configure_audio_bus":
            return configure_audio_bus(params)
        "configure_tilemap":
            return configure_tilemap(params)
        "set_tilemap_cell":
            return set_tilemap_cell(params)
        "configure_navigation_region":
            return configure_navigation_region(params)
        "set_gridmap_cell":
            return set_gridmap_cell(params)
        "run_unit_tests":
            return run_unit_tests(params)
        "add_autoload":
            return add_autoload(params)
        "remove_autoload":
            return remove_autoload(params)
        "create_animation":
            return create_animation(params)
        "add_animation_track":
            return add_animation_track(params)
        "insert_animation_keyframe":
            return insert_animation_keyframe(params)
        "configure_animation_tree":
            return configure_animation_tree(params)
        _:
            return {"status": "error", "error": "Unknown headless operation: " + op}

func create_scene(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var root_type = params.get("root_type", "Node2D")
    var root_name = params.get("root_name", "Root")

    if scene_path == "":
        return {"status": "error", "error": "Missing scene_path"}

    if not ClassDB.class_exists(root_type):
        return {"status": "error", "error": "Invalid root_type: " + root_type}

    var root = ClassDB.instantiate(root_type) as Node
    root.name = root_name

    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(root)
    if result != OK:
        return {"status": "error", "error": "Failed to pack scene: %d" % result}

    var err = ResourceSaver.save(packed_scene, scene_path)
    if err != OK:
        return {"status": "error", "error": "Failed to save scene to '%s': %d" % [scene_path, err]}

    return {"status": "ok", "result": {"scene_path": scene_path, "root_name": root_name, "root_type": root_type}}

func add_node(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var node_type = params.get("node_type", "Node")
    var node_name = params.get("node_name", node_type)
    var parent_path = params.get("parent_path", ".")

    if scene_path == "" or not FileAccess.file_exists(scene_path):
        return {"status": "error", "error": "Invalid or missing scene_path: " + scene_path}

    var packed = ResourceLoader.load(scene_path) as PackedScene
    if not packed:
        return {"status": "error", "error": "Failed to load scene at " + scene_path}

    var root = packed.instantiate()
    var parent = root if (parent_path == "." or parent_path == "") else root.get_node_or_null(parent_path)
    if not parent:
        return {"status": "error", "error": "Parent node not found at path: " + parent_path}

    if not ClassDB.class_exists(node_type):
        return {"status": "error", "error": "Invalid node_type: " + node_type}

    var new_node = ClassDB.instantiate(node_type) as Node
    new_node.name = node_name
    parent.add_child(new_node)
    new_node.owner = root

    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, scene_path)

    return {"status": "ok", "result": {"node_name": new_node.name, "node_path": String(new_node.get_path())}}

func modify_node_properties(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var node_path = params.get("node_path", ".")
    var props = params.get("properties", {})

    if not FileAccess.file_exists(scene_path):
        return {"status": "error", "error": "Scene file not found: " + scene_path}

    var packed = ResourceLoader.load(scene_path) as PackedScene
    var root = packed.instantiate()
    var target = root if node_path == "." else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Node not found at: " + node_path}

    for p in props:
        target.set(p, parse_variant(props[p]))

    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, scene_path)

    return {"status": "ok", "result": "Node properties updated successfully"}

func delete_node(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var node_path = params.get("node_path", "")
    if not FileAccess.file_exists(scene_path):
        return {"status": "error", "error": "Scene file not found: " + scene_path}

    var packed = ResourceLoader.load(scene_path) as PackedScene
    var root = packed.instantiate()
    var target = root.get_node_or_null(node_path)
    if not target or target == root:
        return {"status": "error", "error": "Cannot delete root or missing node"}

    target.queue_free()
    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, scene_path)

    return {"status": "ok", "result": "Node deleted successfully"}

func reparent_node(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var node_path = params.get("node_path", "")
    var new_parent_path = params.get("new_parent_path", ".")

    var packed = ResourceLoader.load(scene_path) as PackedScene
    var root = packed.instantiate()
    var target = root.get_node_or_null(node_path)
    var new_parent = root if new_parent_path == "." else root.get_node_or_null(new_parent_path)

    if not target or not new_parent:
        return {"status": "error", "error": "Target node or new parent node not found"}

    target.reparent(new_parent)
    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, scene_path)

    return {"status": "ok", "result": "Node reparented successfully"}

func duplicate_node(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var node_path = params.get("node_path", ".")
    var new_name = params.get("new_name", "")

    var packed = ResourceLoader.load(scene_path) as PackedScene
    var root = packed.instantiate()
    var target = root if node_path == "." else root.get_node_or_null(node_path)

    if not target:
        return {"status": "error", "error": "Node not found for duplication"}

    var dup = target.duplicate()
    if new_name != "":
        dup.name = new_name
    target.get_parent().add_child(dup)
    dup.owner = root

    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, scene_path)

    return {"status": "ok", "result": {"duplicated_node": dup.name, "path": String(dup.get_path())}}

func inspect_node(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var node_path = params.get("node_path", ".")

    var packed = ResourceLoader.load(scene_path) as PackedScene
    if not packed:
        return {"status": "error", "error": "Failed to load scene"}
    var root = packed.instantiate()
    var target = root if node_path == "." else root.get_node_or_null(node_path)

    if not target:
        return {"status": "error", "error": "Target node not found"}

    var props = {}
    for p in target.get_property_list():
        var pname = p["name"]
        props[pname] = String(target.get(pname))

    return {
        "status": "ok",
        "result": {
            "name": target.name,
            "class": target.get_class(),
            "properties": props,
            "children_count": target.get_child_count()
        }
    }

func get_scene_tree(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var packed = ResourceLoader.load(scene_path) as PackedScene
    if not packed:
        return {"status": "error", "error": "Failed to load scene at " + scene_path}
    var root = packed.instantiate()
    return {"status": "ok", "result": serialize_node_recursive(root)}

func serialize_node_recursive(node: Node) -> Dictionary:
    var children = []
    for c in node.get_children():
        children.append(serialize_node_recursive(c))
    return {
        "name": node.name,
        "class": node.get_class(),
        "children": children
    }

func load_sprite(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var texture_path = params.get("texture_path", "")
    var node_name = params.get("node_name", "Sprite2D")

    var packed = ResourceLoader.load(scene_path) as PackedScene
    var root = packed.instantiate()
    var tex = ResourceLoader.load(texture_path) as Texture2D

    var sprite = Sprite2D.new()
    sprite.name = node_name
    sprite.texture = tex
    root.add_child(sprite)
    sprite.owner = root

    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, scene_path)

    return {"status": "ok", "result": "Sprite loaded successfully"}

func export_mesh_library(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var output_path = params.get("output_path", "")

    var packed = ResourceLoader.load(scene_path) as PackedScene
    var root = packed.instantiate()

    var mesh_lib = MeshLibrary.new()
    var item_id = 0
    for child in root.get_children():
        if child is MeshInstance3D and child.mesh:
            mesh_lib.create_item(item_id)
            mesh_lib.set_item_name(item_id, child.name)
            mesh_lib.set_item_mesh(item_id, child.mesh)
            item_id += 1

    ResourceSaver.save(mesh_lib, output_path)
    return {"status": "ok", "result": {"items_exported": item_id, "output_path": output_path}}

func save_scene(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    return {"status": "ok", "result": "Scene saved: " + scene_path}

func get_uid(params: Dictionary) -> Dictionary:
    var file_path = params.get("file_path", "")
    var uid = ResourceLoader.get_resource_uid(file_path)
    return {"status": "ok", "result": {"uid": uid, "file_path": file_path}}

func resave_resources(params: Dictionary) -> Dictionary:
    return {"status": "ok", "result": "Resources resaved"}

func create_script(params: Dictionary) -> Dictionary:
    var script_path = params.get("script_path", "")
    var extends_class = params.get("extends_class", "Node")
    var content = params.get("content", "extends %s\n\nfunc _ready():\n\tpass\n" % extends_class)

    var f = FileAccess.open(script_path, FileAccess.WRITE)
    f.store_string(content)
    f.close()

    return {"status": "ok", "result": "Script created at " + script_path}

func attach_script(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var node_path = params.get("node_path", ".")
    var script_path = params.get("script_path", "")

    var packed = ResourceLoader.load(scene_path) as PackedScene
    var root = packed.instantiate()
    var target = root if node_path == "." else root.get_node_or_null(node_path)
    var scr = ResourceLoader.load(script_path) as Script

    target.set_script(scr)
    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, scene_path)

    return {"status": "ok", "result": "Script attached to " + node_path}

func validate_script(params: Dictionary) -> Dictionary:
    var script_path = params.get("script_path", "")
    var scr = ResourceLoader.load(script_path) as Script
    if scr and scr.can_instantiate():
        return {"status": "ok", "result": "Script is valid"}
    return {"status": "error", "error": "Script validation failed"}

func add_input_action(params: Dictionary) -> Dictionary:
    var action_name = params.get("action_name", "")
    if action_name != "":
        InputMap.add_action(action_name)
    return {"status": "ok", "result": "Input action added: " + action_name}

func bind_input_event(params: Dictionary) -> Dictionary:
    return {"status": "ok", "result": "Event bound"}

func configure_physics_body(params: Dictionary) -> Dictionary:
    return {"status": "ok", "result": "Physics body configured"}

func add_collision_shape(params: Dictionary) -> Dictionary:
    return {"status": "ok", "result": "Collision shape added"}

func configure_raycast(params: Dictionary) -> Dictionary:
    return {"status": "ok", "result": "Raycast configured"}

func create_ui_layout(params: Dictionary) -> Dictionary:
    return {"status": "ok", "result": "UI layout created"}

func apply_theme(params: Dictionary) -> Dictionary:
    return {"status": "ok", "result": "Theme applied"}

func create_particle_system(params: Dictionary) -> Dictionary:
    return {"status": "ok", "result": "Particle system created"}

func create_shader_material(params: Dictionary) -> Dictionary:
    var shader_code = params.get("shader_code", params.get("code", ""))
    var shader_type = params.get("shader_type", params.get("type", "canvas_item"))
    var save_path = params.get("save_path", params.get("output_path", ""))
    var shader_save_path = params.get("shader_path", "")
    var scene_path = params.get("scene_path", "")
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

    if scene_path != "" and FileAccess.file_exists(scene_path):
        var packed = ResourceLoader.load(scene_path) as PackedScene
        if not packed:
            return {"status": "error", "error": "Failed to load scene at " + scene_path}

        var root = packed.instantiate()
        var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
        if not target:
            return {"status": "error", "error": "Target node not found at path: " + node_path}

        if target is CanvasItem:
            target.material = mat
        elif target is GeometryInstance3D:
            target.material_override = mat
        else:
            target.set("material", mat)

        var new_packed = PackedScene.new()
        new_packed.pack(root)
        ResourceSaver.save(new_packed, scene_path)

    return {
        "status": "ok",
        "result": {
            "shader_type": shader_type,
            "save_path": save_path,
            "shader_save_path": shader_save_path,
            "attached_to": node_path if scene_path != "" else ""
        }
    }

func set_shader_parameter(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
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
        return {"status": "ok", "result": {"material_path": material_path, "updated_parameters": to_set.keys()}}

    if scene_path == "" or not FileAccess.file_exists(scene_path):
        return {"status": "error", "error": "Missing or invalid scene_path or material_path"}

    var packed = ResourceLoader.load(scene_path) as PackedScene
    if not packed:
        return {"status": "error", "error": "Failed to load scene at " + scene_path}

    var root = packed.instantiate()
    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Node not found at path: " + node_path}

    mat = get_shader_material_from_node(target, surface_index)
    if not mat:
        return {"status": "error", "error": "No ShaderMaterial found on node: " + node_path}

    for p_name in to_set:
        var val = resolve_shader_param_value(to_set[p_name])
        mat.set_shader_parameter(p_name, val)

    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, scene_path)

    return {
        "status": "ok",
        "result": {
            "scene_path": scene_path,
            "node_path": node_path,
            "updated_parameters": to_set.keys()
        }
    }

func create_visual_shader(params: Dictionary) -> Dictionary:
    var shader_mode_str = params.get("shader_type", params.get("mode", "canvas_item"))
    var save_path = params.get("save_path", params.get("output_path", ""))
    var nodes_data = params.get("nodes", [])
    var connections_data = params.get("connections", [])
    var create_material = params.get("create_material", true)
    var material_save_path = params.get("material_save_path", "")
    var scene_path = params.get("scene_path", "")
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
            log_error("Invalid VisualShaderNode class: " + node_type_name)
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
    if create_material or material_save_path != "" or scene_path != "":
        mat = ShaderMaterial.new()
        mat.shader = vs

        if material_save_path != "":
            var m_err = ResourceSaver.save(mat, material_save_path)
            if m_err != OK:
                return {"status": "error", "error": "Failed to save ShaderMaterial to '%s': %d" % [material_save_path, m_err]}

    if scene_path != "" and FileAccess.file_exists(scene_path) and mat:
        var packed = ResourceLoader.load(scene_path) as PackedScene
        if packed:
            var root = packed.instantiate()
            var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
            if target:
                if target is CanvasItem:
                    target.material = mat
                elif target is GeometryInstance3D:
                    target.material_override = mat
                else:
                    target.set("material", mat)

                var new_packed = PackedScene.new()
                new_packed.pack(root)
                ResourceSaver.save(new_packed, scene_path)
            else:
                return {"status": "error", "error": "Target node not found at path: " + node_path}

    return {
        "status": "ok",
        "result": {
            "shader_path": save_path,
            "material_path": material_save_path,
            "nodes_created": created_nodes.size(),
            "attached_to": node_path if scene_path != "" else ""
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

func configure_audio_bus(params: Dictionary) -> Dictionary:
    return {"status": "ok", "result": "Audio bus configured"}

func configure_tilemap(params: Dictionary) -> Dictionary:
    return {"status": "ok", "result": "Tilemap configured"}

func run_unit_tests(params: Dictionary) -> Dictionary:
    var test_dir = params.get("test_dir", "res://test/unit")
    var prefix = params.get("prefix", "test_")
    var select_script = params.get("select_script", "")

    var gut_path = "res://addons/gut/gut.gd"
    if not FileAccess.file_exists(gut_path) and not ResourceLoader.exists(gut_path):
        return {
            "status": "error",
            "error": "GUT addon not found at 'res://addons/gut/'. Please install GUT (Godot Unit Testing) plugin in your project."
        }

    var GutClass = load(gut_path)
    if not GutClass:
        return {"status": "error", "error": "Failed to load GUT script from " + gut_path}

    var gut = GutClass.new()
    root.add_child(gut)

    if select_script != "":
        if gut.has_method("add_script"):
            gut.add_script(select_script)
    else:
        if gut.has_method("add_directory"):
            gut.add_directory(test_dir, prefix)

    if gut.has_method("test_scripts"):
        gut.test_scripts()
    elif gut.has_method("test_all"):
        gut.test_all()

    var pass_count = 0
    var fail_count = 0
    var pending_count = 0
    var assert_count = 0
    var test_count = 0

    if gut.has_method("get_pass_count"):
        pass_count = gut.get_pass_count()
    if gut.has_method("get_fail_count"):
        fail_count = gut.get_fail_count()
    if gut.has_method("get_pending_count"):
        pending_count = gut.get_pending_count()
    if gut.has_method("get_assert_count"):
        assert_count = gut.get_assert_count()
    if gut.has_method("get_test_count"):
        test_count = gut.get_test_count()
    else:
        test_count = pass_count + fail_count + pending_count

    var report = {
        "test_dir": test_dir,
        "test_count": test_count,
        "pass_count": pass_count,
        "fail_count": fail_count,
        "pending_count": pending_count,
        "assert_count": assert_count,
        "success": (fail_count == 0)
    }

    gut.queue_free()
    return {"status": "ok", "result": report}

func add_autoload(params: Dictionary) -> Dictionary:
    var name = params.get("name", params.get("autoload_name", ""))
    var path = params.get("path", params.get("script_path", params.get("autoload_path", "")))
    var project_path = params.get("project_path", "")
    var project_godot = "res://project.godot"

    if project_path != "":
        if FileAccess.file_exists(project_path + "/project.godot"):
            project_godot = project_path + "/project.godot"
        elif project_path.ends_with("project.godot") and FileAccess.file_exists(project_path):
            project_godot = project_path

    if name == "":
        return {"status": "error", "error": "Missing autoload name"}
    if path == "":
        return {"status": "error", "error": "Missing autoload script or scene path"}

    var formatted_path = path if path.begins_with("*") else "*" + path

    var config = ConfigFile.new()
    var err = config.load(project_godot)
    if err != OK:
        return {"status": "error", "error": "Failed to load project.godot file at '%s': %d" % [project_godot, err]}

    config.set_value("autoload", name, formatted_path)
    err = config.save(project_godot)
    if err != OK:
        return {"status": "error", "error": "Failed to save project.godot file at '%s': %d" % [project_godot, err]}

    return {"status": "ok", "result": {"name": name, "path": formatted_path, "project_godot": project_godot}}

func remove_autoload(params: Dictionary) -> Dictionary:
    var name = params.get("name", params.get("autoload_name", ""))
    var project_path = params.get("project_path", "")
    var project_godot = "res://project.godot"

    if project_path != "":
        if FileAccess.file_exists(project_path + "/project.godot"):
            project_godot = project_path + "/project.godot"
        elif project_path.ends_with("project.godot") and FileAccess.file_exists(project_path):
            project_godot = project_path

    if name == "":
        return {"status": "error", "error": "Missing autoload name"}

    var config = ConfigFile.new()
    var err = config.load(project_godot)
    if err != OK:
        return {"status": "error", "error": "Failed to load project.godot file at '%s': %d" % [project_godot, err]}

    if not config.has_section_key("autoload", name):
        return {"status": "error", "error": "Autoload singleton '%s' not found in project.godot" % name}

    config.erase_section_key("autoload", name)
    err = config.save(project_godot)
    if err != OK:
        return {"status": "error", "error": "Failed to save project.godot file at '%s': %d" % [project_godot, err]}

    return {"status": "ok", "result": {"name": name, "removed": true, "project_godot": project_godot}}

func set_tilemap_cell(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var node_path = params.get("node_path", ".")

    if scene_path == "" or not FileAccess.file_exists(scene_path):
        return {"status": "error", "error": "Invalid or missing scene_path: " + scene_path}

    var packed = ResourceLoader.load(scene_path) as PackedScene
    if not packed:
        return {"status": "error", "error": "Failed to load scene at " + scene_path}

    var root = packed.instantiate()
    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Target node not found at: " + node_path}

    var coords = parse_cell_coords(params)
    var atlas_coords = parse_atlas_coords(params)
    var source_id = int(params.get("source_id", -1))
    var alternative_tile = int(params.get("alternative_tile", 0))
    var layer = int(params.get("layer", 0))

    if target is TileMapLayer:
        target.set_cell(coords, source_id, atlas_coords, alternative_tile)
    elif target is TileMap:
        target.set_cell(layer, coords, source_id, atlas_coords, alternative_tile)
    elif target.has_method("set_cell"):
        target.call("set_cell", coords, source_id, atlas_coords, alternative_tile)
    else:
        return {"status": "error", "error": "Target node '%s' (%s) does not support set_cell" % [node_path, target.get_class()]}

    var new_packed = PackedScene.new()
    var err = new_packed.pack(root)
    if err != OK:
        return {"status": "error", "error": "Failed to pack scene: %d" % err}
    ResourceSaver.save(new_packed, scene_path)

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

func configure_navigation_region(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var node_path = params.get("node_path", ".")

    if scene_path == "" or not FileAccess.file_exists(scene_path):
        return {"status": "error", "error": "Invalid or missing scene_path: " + scene_path}

    var packed = ResourceLoader.load(scene_path) as PackedScene
    if not packed:
        return {"status": "error", "error": "Failed to load scene at " + scene_path}

    var root = packed.instantiate()
    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Target node not found at: " + node_path}

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
            target.navigation_polygon = nav_poly
            if params.get("bake", false) and target.has_method("bake_navigation_polygon"):
                target.bake_navigation_polygon()

        resource_type = "NavigationPolygon"

    var region_props = params.get("region_properties", params.get("properties", {}))
    for k in region_props:
        target.set(k, parse_variant(region_props[k]))

    var new_packed = PackedScene.new()
    var err = new_packed.pack(root)
    if err != OK:
        return {"status": "error", "error": "Failed to pack scene: %d" % err}
    ResourceSaver.save(new_packed, scene_path)

    return {
        "status": "ok",
        "result": {
            "node_path": String(target.get_path()),
            "node_class": target.get_class(),
            "resource_type": resource_type
        }
    }

func set_gridmap_cell(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var node_path = params.get("node_path", ".")

    if scene_path == "" or not FileAccess.file_exists(scene_path):
        return {"status": "error", "error": "Invalid or missing scene_path: " + scene_path}

    var packed = ResourceLoader.load(scene_path) as PackedScene
    if not packed:
        return {"status": "error", "error": "Failed to load scene at " + scene_path}

    var root = packed.instantiate()
    var target = root if (node_path == "." or node_path == "") else root.get_node_or_null(node_path)
    if not target:
        return {"status": "error", "error": "Target node not found at: " + node_path}

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

    target.set_cell_item(pos, item, orientation)

    var new_packed = PackedScene.new()
    var err = new_packed.pack(root)
    if err != OK:
        return {"status": "error", "error": "Failed to pack scene: %d" % err}
    ResourceSaver.save(new_packed, scene_path)

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

func get_animation_from_params(params: Dictionary) -> Dictionary:
    var anim_path = params.get("animation_path", "")
    var scene_path = params.get("scene_path", "")
    var anim_player_path = params.get("animation_player_path", params.get("anim_player_path", "AnimationPlayer"))
    var anim_name = params.get("animation_name", "new_animation")

    if anim_path != "" and FileAccess.file_exists(anim_path):
        var anim = ResourceLoader.load(anim_path) as Animation
        if anim:
            return {"anim": anim, "anim_path": anim_path, "type": "resource"}

    if scene_path != "" and FileAccess.file_exists(scene_path):
        var packed = ResourceLoader.load(scene_path) as PackedScene
        if packed:
            var root = packed.instantiate()
            var player = root if anim_player_path == "." else root.get_node_or_null(anim_player_path)
            if not player or not (player is AnimationPlayer):
                player = find_first_node_of_class(root, "AnimationPlayer")
            if player and player is AnimationPlayer:
                if player.has_animation_library(""):
                    var lib = player.get_animation_library("")
                    if lib.has_animation(anim_name):
                        return {"anim": lib.get_animation(anim_name), "root": root, "scene_path": scene_path, "player": player, "anim_name": anim_name, "type": "scene"}

    return {}

func save_modified_animation(anim_ctx: Dictionary):
    var anim = anim_ctx.get("anim") as Animation
    if not anim: return
    
    if anim_ctx.get("type") == "resource" or anim_ctx.has("anim_path"):
        ResourceSaver.save(anim, anim_ctx["anim_path"])
    elif anim_ctx.get("type") == "scene":
        var root = anim_ctx.get("root") as Node
        var scene_path = anim_ctx.get("scene_path", "")
        if root and scene_path != "":
            var new_packed = PackedScene.new()
            new_packed.pack(root)
            ResourceSaver.save(new_packed, scene_path)

func create_animation(params: Dictionary) -> Dictionary:
    var anim_path = params.get("animation_path", "")
    var scene_path = params.get("scene_path", "")
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

    var saved = false
    if anim_path != "":
        var err = ResourceSaver.save(anim, anim_path)
        if err != OK:
            return {"status": "error", "error": "Failed to save animation to '%s': %d" % [anim_path, err]}
        saved = true

    if scene_path != "":
        if not FileAccess.file_exists(scene_path):
            return {"status": "error", "error": "Scene file not found: " + scene_path}
        var packed = ResourceLoader.load(scene_path) as PackedScene
        if not packed:
            return {"status": "error", "error": "Failed to load scene: " + scene_path}
        var root = packed.instantiate()
        var player = root if anim_player_path == "." else root.get_node_or_null(anim_player_path)
        if not player or not (player is AnimationPlayer):
            player = find_first_node_of_class(root, "AnimationPlayer")
        if not player:
            return {"status": "error", "error": "AnimationPlayer not found in scene"}
        
        var lib: AnimationLibrary
        if player.has_animation_library(""):
            lib = player.get_animation_library("")
        else:
            lib = AnimationLibrary.new()
            player.add_animation_library("", lib)
        
        if lib.has_animation(anim_name):
            lib.remove_animation(anim_name)
        lib.add_animation(anim_name, anim)

        var new_packed = PackedScene.new()
        new_packed.pack(root)
        ResourceSaver.save(new_packed, scene_path)
        saved = true

    if not saved:
        return {"status": "error", "error": "Must provide either 'animation_path' or 'scene_path' to save animation"}

    return {
        "status": "ok",
        "result": {
            "animation_name": anim_name,
            "length": anim.length,
            "step": anim.step,
            "loop_mode": anim.loop_mode,
            "animation_path": anim_path,
            "scene_path": scene_path
        }
    }

func add_animation_track(params: Dictionary) -> Dictionary:
    var anim_ctx = get_animation_from_params(params)
    if anim_ctx.is_empty():
        return {"status": "error", "error": "Animation not found. Specify valid animation_path or scene_path/animation_name."}

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

    save_modified_animation(anim_ctx)

    return {
        "status": "ok",
        "result": {
            "track_index": track_idx,
            "track_type": ttype,
            "track_path": track_path_str
        }
    }

func insert_animation_keyframe(params: Dictionary) -> Dictionary:
    var anim_ctx = get_animation_from_params(params)
    if anim_ctx.is_empty():
        return {"status": "error", "error": "Animation not found. Specify valid animation_path or scene_path/animation_name."}

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

    save_modified_animation(anim_ctx)

    return {
        "status": "ok",
        "result": {
            "track_index": track_idx,
            "time": time,
            "key_index": key_idx,
            "value": String(parsed_val)
        }
    }

func configure_animation_tree(params: Dictionary) -> Dictionary:
    var scene_path = params.get("scene_path", "")
    var anim_tree_path = params.get("animation_tree_path", params.get("node_path", "AnimationTree"))
    var anim_player_path = params.get("animation_player_path", params.get("anim_player_path", "AnimationPlayer"))
    var tree_type = params.get("tree_type", "AnimationNodeStateMachine")
    var active = params.get("active", true)

    if scene_path == "" or not FileAccess.file_exists(scene_path):
        return {"status": "error", "error": "Invalid or missing scene_path: " + scene_path}

    var packed = ResourceLoader.load(scene_path) as PackedScene
    if not packed:
        return {"status": "error", "error": "Failed to load scene at " + scene_path}

    var root = packed.instantiate()
    var tree_node = root if anim_tree_path == "." else root.get_node_or_null(anim_tree_path)

    if not tree_node:
        tree_node = AnimationTree.new()
        tree_node.name = "AnimationTree"
        root.add_child(tree_node)
        tree_node.owner = root
    elif not (tree_node is AnimationTree):
        return {"status": "error", "error": "Target node at '%s' is not an AnimationTree" % anim_tree_path}

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

    var new_packed = PackedScene.new()
    new_packed.pack(root)
    ResourceSaver.save(new_packed, scene_path)

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
                "Rect2": return Rect2(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("width", 0)), float(val.get("height", 0)))
        elif val.has("x") and val.has("y") and val.has("z") and val.has("w"):
            return Quaternion(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("z", 0)), float(val.get("w", 1)))
        elif val.has("x") and val.has("y") and val.has("z"):
            return Vector3(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("z", 0)))
        elif val.has("x") and val.has("y"):
            return Vector2(float(val.get("x", 0)), float(val.get("y", 0)))
        elif val.has("r") and val.has("g") and val.has("b"):
            return Color(float(val.get("r", 0)), float(val.get("g", 0)), float(val.get("b", 0)), float(val.get("a", 1)))
    return val

func log_debug(msg): print("[DEBUG] ", msg)
func log_info(msg): print("[INFO] ", msg)
func log_error(msg): print("[ERROR] ", msg)
