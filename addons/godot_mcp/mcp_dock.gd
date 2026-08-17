@tool
extends Control

var server_node = null
var editor_interface: EditorInterface = null

var status_label: Label
var selection_label: Label
var stats_label: Label
var log_view: RichTextLabel

func _ready():
	custom_minimum_size = Vector2(300, 220)
	_build_ui()
	_update_status()

func _build_ui():
	for child in get_children():
		child.queue_free()

	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# --- Header ---
	var header = HBoxContainer.new()
	var title = Label.new()
	title.text = "🤖 Godot MCP Bridge"
	title.add_theme_font_size_override("font_size", 14)
	header.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	status_label = Label.new()
	status_label.text = "● TCP 6505 (Active)"
	status_label.modulate = Color(0.2, 0.9, 0.4)
	header.add_child(status_label)
	vbox.add_child(header)

	# --- Live Status Bar ---
	var stats_hbox = HBoxContainer.new()
	stats_label = Label.new()
	stats_label.text = "Engine: Godot " + Engine.get_version_info().get("string", "4.x")
	stats_label.modulate = Color(0.7, 0.7, 0.8)
	stats_hbox.add_child(stats_label)

	var stats_spacer = Control.new()
	stats_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_hbox.add_child(stats_spacer)

	selection_label = Label.new()
	selection_label.text = "Selected: (None)"
	selection_label.modulate = Color(0.4, 0.8, 1.0)
	stats_hbox.add_child(selection_label)
	vbox.add_child(stats_hbox)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# --- Live Action Log ---
	var log_label = Label.new()
	log_label.text = "Live Agent Activity Feed:"
	vbox.add_child(log_label)

	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.text = "[color=#888888]Listening for incoming MCP operations on port 6505...[/color]\n"
	vbox.add_child(log_view)

	# --- Quick Action Buttons ---
	var btn_hbox = HBoxContainer.new()
	var btn_profile = Button.new()
	btn_profile.text = "📊 Profile Engine"
	btn_profile.pressed.connect(_on_profile_pressed)
	btn_hbox.add_child(btn_profile)

	var btn_frame = Button.new()
	btn_frame.text = "🎯 Frame in 3D"
	btn_frame.pressed.connect(_on_frame_pressed)
	btn_hbox.add_child(btn_frame)

	var btn_clear = Button.new()
	btn_clear.text = "🧹 Clear Feed"
	btn_clear.pressed.connect(func(): log_view.clear(); log_view.append_text("[color=#888888]Log cleared.[/color]\n"))
	btn_hbox.add_child(btn_clear)

	vbox.add_child(btn_hbox)

func _process(_delta):
	if Engine.is_editor_hint() and editor_interface:
		var selection = editor_interface.get_selection().get_selected_nodes()
		if selection.size() > 0:
			var n = selection[0]
			selection_label.text = "Selected: %s (%s)" % [n.name, n.get_class()]
		else:
			selection_label.text = "Selected: (None)"

func append_log(command_name: String, details: String = ""):
	if not log_view:
		return
	var time_dict = Time.get_time_dict_from_system()
	var time_str = "%02d:%02d:%02d" % [time_dict.hour, time_dict.minute, time_dict.second]
	var text = "[color=#55bbff][%s][/color] [b]%s[/b] %s\n" % [time_str, command_name, details]
	log_view.append_text(text)

func _update_status():
	if status_label:
		if server_node and server_node.peers.size() > 0:
			status_label.text = "● Connected (%d client)" % server_node.peers.size()
			status_label.modulate = Color(0.2, 1.0, 0.4)
		else:
			status_label.text = "● Listening (Port 6505)"
			status_label.modulate = Color(0.4, 0.8, 1.0)

func _on_profile_pressed():
	if server_node:
		var metrics = server_node.get_performance_metrics_in_editor({})
		var res = metrics.get("result", {})
		append_log("Profile", "FPS: %s | Static Mem: %.1f MB | Nodes: %s" % [
			str(res.get("time_fps", 0)),
			float(res.get("memory_static", 0)) / (1024.0 * 1024.0),
			str(res.get("object_node_count", 0))
		])

func _on_frame_pressed():
	if editor_interface:
		var selection = editor_interface.get_selection().get_selected_nodes()
		if selection.size() > 0:
			var n = selection[0]
			if n is Node3D:
				editor_interface.get_editor_viewport_3d(0)
				append_log("Viewport Focus", "Focused on %s" % n.name)
