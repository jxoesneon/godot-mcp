@tool
extends EditorPlugin

var mcp_server_script = preload("res://addons/godot_mcp/mcp_server.gd")
var server_node = null

func _enter_tree():
    print("[Godot MCP Pro Bridge] Initializing in-editor server plugin...")
    server_node = mcp_server_script.new()
    server_node.editor_interface = get_editor_interface()
    server_node.undo_redo_manager = get_undo_redo()
    add_child(server_node)
    print("[Godot MCP Pro Bridge] Server listening on port 6505")

func _exit_tree():
    print("[Godot MCP Pro Bridge] Shutting down in-editor server plugin...")
    if server_node:
        server_node.stop_server()
        server_node.queue_free()
        server_node = null
