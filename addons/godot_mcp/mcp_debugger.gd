@tool
extends EditorDebuggerPlugin

var recent_errors: Array = []
var max_errors: int = 50
var active_sessions: Array = []

func _setup_session(session_id: int):
	var session = get_session(session_id)
	if not session:
		return
	active_sessions.append(session)
	session.stopped.connect(func(): _on_session_event(session_id, "stopped"))
	session.breaked.connect(func(can_debug): _on_session_event(session_id, "breaked", {"can_debug": can_debug}))
	session.continued.connect(func(): _on_session_event(session_id, "continued"))

func _on_session_event(session_id: int, event_name: String, data: Dictionary = {}):
	var entry = {
		"timestamp": Time.get_unix_time_from_system(),
		"session_id": session_id,
		"event": event_name,
		"data": data
	}
	_add_log(entry)

func record_error(error_msg: String, file: String = "", line: int = 0, function: String = ""):
	var entry = {
		"timestamp": Time.get_unix_time_from_system(),
		"type": "error",
		"message": error_msg,
		"file": file,
		"line": line,
		"function": function
	}
	_add_log(entry)

func _add_log(entry: Dictionary):
	recent_errors.append(entry)
	if recent_errors.size() > max_errors:
		recent_errors.pop_front()

func get_errors() -> Array:
	return recent_errors.duplicate()

func clear_errors():
	recent_errors.clear()
