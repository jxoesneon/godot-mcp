@tool
extends EditorPlugin

var mcp_server_script = preload("res://addons/godot_mcp/mcp_server.gd")
var mcp_dock_script = preload("res://addons/godot_mcp/mcp_dock.gd")
var mcp_debugger_script = preload("res://addons/godot_mcp/mcp_debugger.gd")

var server_node = null
var dock_instance = null
var debugger_instance = null

func _enter_tree():
	print("[Godot MCP Pro Bridge] Initializing in-editor server and deep tool integration...")
	
	# 1. Start Server Node
	server_node = mcp_server_script.new()
	server_node.editor_interface = get_editor_interface()
	server_node.undo_redo_manager = get_undo_redo()
	add_child(server_node)

	# 2. Setup Debugger Telemetry Plugin
	debugger_instance = mcp_debugger_script.new()
	debugger_instance.editor_interface = get_editor_interface()
	add_debugger_plugin(debugger_instance)
	server_node.debugger_plugin = debugger_instance

	# 3. Setup Interactive Bottom Panel Dock
	dock_instance = mcp_dock_script.new()
	dock_instance.server_node = server_node
	dock_instance.editor_interface = get_editor_interface()
	server_node.dock_instance = dock_instance
	add_control_to_bottom_panel(dock_instance, "🤖 Godot MCP")

	print("[Godot MCP Pro Bridge] Server listening on port 6505. AI Dock and Debugger attached.")

func _exit_tree():
	print("[Godot MCP Pro Bridge] Shutting down in-editor server and dock...")
	if dock_instance:
		remove_control_from_bottom_panel(dock_instance)
		dock_instance.queue_free()
		dock_instance = null

	if debugger_instance:
		remove_debugger_plugin(debugger_instance)
		debugger_instance = null

	if server_node:
		server_node.stop_server()
		server_node.queue_free()
		server_node = null
