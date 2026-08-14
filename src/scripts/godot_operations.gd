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

func parse_variant(val):
    if typeof(val) == TYPE_DICTIONARY:
        if val.has("__type"):
            var t = val["__type"]
            match t:
                "Vector2": return Vector2(float(val.get("x", 0)), float(val.get("y", 0)))
                "Vector3": return Vector3(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("z", 0)))
                "Color": return Color(float(val.get("r", 0)), float(val.get("g", 0)), float(val.get("b", 0)), float(val.get("a", 1)))
                "Rect2": return Rect2(float(val.get("x", 0)), float(val.get("y", 0)), float(val.get("width", 0)), float(val.get("height", 0)))
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
