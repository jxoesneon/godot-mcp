@tool
extends EditorDebuggerPlugin

# --- Configuration ---
var max_errors: int = 200
var editor_interface: EditorInterface = null

# --- State ---
var recent_errors: Array = []
var active_sessions: Array = []
var _connected_debuggers: Array = []
var _dedup_map: Dictionary = {}
var _last_stack_dump: Array = []
var _session_id_for_debugger: Dictionary = {}

# --- EditorLog::MessageType constants (from editor_log.h) ---
const MSG_TYPE_STD = 0
const MSG_TYPE_ERROR = 1
const MSG_TYPE_STD_RICH = 2
const MSG_TYPE_WARNING = 3
const MSG_TYPE_EDITOR = 4

func _setup_session(session_id: int):
	var session = get_session(session_id)
	if not session:
		return
	active_sessions.append(session)
	session.stopped.connect(func(): _on_session_event(session_id, "stopped"))
	session.breaked.connect(func(can_debug): _on_session_event(session_id, "breaked", {"can_debug": can_debug}))
	session.continued.connect(func(): _on_session_event(session_id, "continued"))
	# Connect to ScriptEditorDebugger nodes to capture runtime messages.
	# Built-in messages like "error" are intercepted by parse_message_handlers
	# before reaching plugins_capture, so _has_capture/_capture cannot see them.
	# Instead, we connect to the debug_data signal which is emitted for ALL messages.
	call_deferred("_connect_debugger_nodes")

# --- Debugger node discovery ---
# ScriptEditorDebugger nodes are children of EditorDebuggerNode (a bottom panel dock).
# We traverse the editor tree from EditorInterface.get_base_control() to find them
# and connect to their debug_data(String, Array) and output(String, int) signals.
func _connect_debugger_nodes():
	if not editor_interface:
		return
	var base = editor_interface.get_base_control()
	if not base:
		return
	_find_and_connect_debuggers(base)

func _find_and_connect_debuggers(node: Node):
	if node == null or not is_instance_valid(node):
		return
	if node.has_signal("debug_data") and not _connected_debuggers.has(node):
		var connected = false
		var err = node.connect("debug_data", _on_debug_data)
		if err == OK:
			connected = true
		if node.has_signal("output"):
			node.connect("output", _on_output)
		if connected:
			_connected_debuggers.append(node)
	for child in node.get_children():
		_find_and_connect_debuggers(child)

# --- Message handlers ---
func _on_debug_data(msg: String, data: Array):
	match msg:
		"error":
			_parse_error_message(data)
		"stack_dump":
			_parse_stack_dump(data)
		"debug_enter":
			_parse_debug_enter(data)
		"debug_exit":
			_last_stack_dump.clear()

func _on_output(text: String, level: int):
	# level uses EditorLog::MessageType: 0=STD, 1=ERROR, 2=STD_RICH, 3=WARNING, 4=EDITOR
	if level == MSG_TYPE_ERROR:
		var entry = {
			"timestamp": Time.get_unix_time_from_system(),
			"type": "output_error",
			"severity": "error",
			"message": text,
			"raw_level": level
		}
		_add_log(entry)
	elif level == MSG_TYPE_WARNING:
		var entry = {
			"timestamp": Time.get_unix_time_from_system(),
			"type": "output_warning",
			"severity": "warning",
			"message": text,
			"raw_level": level
		}
		_add_log(entry)

# --- OutputError deserialization ---
# Format from debugger_marshalls.cpp OutputError::serialize():
# [hr, min, sec, msec, source_file, source_func, source_line, error, error_descr, warning, stack_size, ...frames]
# Each frame is (file, func, line) — 3 elements per frame.
func _parse_error_message(data: Array):
	if data.size() < 11:
		# Malformed error message, store raw
		var entry = {
			"timestamp": Time.get_unix_time_from_system(),
			"type": "runtime_error",
			"severity": "error",
			"message": "Malformed error data (size < 11)",
			"raw_data": data.duplicate()
		}
		_add_log(entry)
		return

	var hr = int(data[0])
	var min_val = int(data[1])
	var sec = int(data[2])
	var msec = int(data[3])
	var source_file = str(data[4])
	var source_func = str(data[5])
	var source_line = int(data[6])
	var error_msg = str(data[7])
	var error_descr = str(data[8])
	var is_warning = bool(data[9])
	var stack_size = int(data[10])

	var stack_frames = []
	var idx = 11
	for i in range(stack_size / 3):
		if idx + 2 < data.size():
			stack_frames.append({
				"file": str(data[idx]),
				"func": str(data[idx + 1]),
				"line": int(data[idx + 2])
			})
			idx += 3

	var time_str = "%02d:%02d:%02d:%03d" % [hr, min_val, sec, msec]
	var severity = "warning" if is_warning else "error"

	# Build the primary message: prefer error_descr (human-readable) over error (condition code)
	var primary_msg = error_descr if not error_descr.is_empty() else error_msg

	# Dedup key: file + function + line + error condition
	var dedup_key = "%s|%s|%d|%s" % [source_file, source_func, source_line, error_msg]

	var entry = {
		"timestamp": Time.get_unix_time_from_system(),
		"type": "runtime_error",
		"severity": severity,
		"time": time_str,
		"message": primary_msg,
		"error": error_msg,
		"error_description": error_descr,
		"file": source_file,
		"line": source_line,
		"function": source_func,
		"stack_trace": stack_frames,
		"dedup_key": dedup_key,
		"repeat_count": 1
	}

	# Deduplicate: if same error seen before, increment count but don't add new entry
	if _dedup_map.has(dedup_key):
		var existing_idx = _dedup_map[dedup_key]
		if existing_idx >= 0 and existing_idx < recent_errors.size():
			recent_errors[existing_idx]["repeat_count"] = int(recent_errors[existing_idx].get("repeat_count", 1)) + 1
			recent_errors[existing_idx]["last_seen"] = entry["timestamp"]
		return

	# Add new entry and track its index for dedup
	_add_log(entry)
	_dedup_map[dedup_key] = recent_errors.size() - 1

# --- Stack dump deserialization ---
# Format from debugger_marshalls.cpp ScriptStackDump::serialize():
# [frame_count, file1, line1, func1, file2, line2, func2, ...]
func _parse_stack_dump(data: Array):
	if data.size() < 1:
		return
	var frame_count = int(data[0])
	var frames = []
	var idx = 1
	for i in range(frame_count / 3):
		if idx + 2 < data.size():
			frames.append({
				"file": str(data[idx]),
				"line": int(data[idx + 1]),
				"func": str(data[idx + 2])
			})
			idx += 3
	_last_stack_dump = frames

# --- Debug break handler ---
# debug_enter: [can_debug, error_message, has_stackdump, caller_thread_id]
func _parse_debug_enter(data: Array):
	if data.size() < 2:
		return
	var error_msg = str(data[1])
	if error_msg.is_empty():
		return
	var entry = {
		"timestamp": Time.get_unix_time_from_system(),
		"type": "debug_break",
		"severity": "error",
		"message": error_msg,
		"stack_trace": _last_stack_dump.duplicate()
	}
	_add_log(entry)

# --- Session events ---
func _on_session_event(session_id: int, event_name: String, data: Dictionary = {}):
	var entry = {
		"timestamp": Time.get_unix_time_from_system(),
		"session_id": session_id,
		"type": "session_event",
		"event": event_name,
		"data": data
	}
	_add_log(entry)

# --- Storage ---
func _add_log(entry: Dictionary):
	recent_errors.append(entry)
	# Trim oldest entries, updating dedup map indices
	if recent_errors.size() > max_errors:
		var removed = recent_errors.pop_front()
		# Rebuild dedup map indices (shift by -1)
		var new_dedup = {}
		for key in _dedup_map:
			var idx = _dedup_map[key]
			if idx > 0:
				new_dedup[key] = idx - 1
		_dedup_map = new_dedup

func record_error(error_msg: String, file: String = "", line: int = 0, function: String = ""):
	# Manual error recording (for API compatibility)
	var entry = {
		"timestamp": Time.get_unix_time_from_system(),
		"type": "manual_error",
		"severity": "error",
		"message": error_msg,
		"file": file,
		"line": line,
		"function": function
	}
	_add_log(entry)

func get_errors() -> Array:
	return recent_errors.duplicate(true)

func get_errors_filtered(filter: Dictionary = {}) -> Array:
	var result = []
	for entry in recent_errors:
		var match_ok = true
		if filter.has("type") and entry.get("type", "") != filter["type"]:
			match_ok = false
		if filter.has("severity") and entry.get("severity", "") != filter["severity"]:
			match_ok = false
		if filter.has("since") and entry.get("timestamp", 0.0) < float(filter["since"]):
			match_ok = false
		if filter.has("exclude_session_events") and bool(filter["exclude_session_events"]) and entry.get("type", "") == "session_event":
			match_ok = false
		if match_ok:
			result.append(entry)
	return result

func clear_errors():
	recent_errors.clear()
	_dedup_map.clear()

func get_error_counts() -> Dictionary:
	var errors = 0
	var warnings = 0
	var output_errors = 0
	var debug_breaks = 0
	var session_events = 0
	for entry in recent_errors:
		match entry.get("type", ""):
			"runtime_error":
				if entry.get("severity") == "warning":
					warnings += 1
				else:
					errors += 1
			"output_error":
				output_errors += 1
			"debug_break":
				debug_breaks += 1
			"session_event":
				session_events += 1
	return {
		"errors": errors,
		"warnings": warnings,
		"output_errors": output_errors,
		"debug_breaks": debug_breaks,
		"session_events": session_events,
		"total": recent_errors.size()
	}

func get_connected_debugger_count() -> int:
	return _connected_debuggers.size()

# --- Cleanup ---
func _exit_tree():
	for dbg in _connected_debuggers:
		if is_instance_valid(dbg):
			if dbg.is_connected("debug_data", _on_debug_data):
				dbg.disconnect("debug_data", _on_debug_data)
			if dbg.has_signal("output") and dbg.is_connected("output", _on_output):
				dbg.disconnect("output", _on_output)
	_connected_debuggers.clear()
