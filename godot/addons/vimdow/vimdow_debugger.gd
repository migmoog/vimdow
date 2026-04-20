@tool
class_name VimdowDebugger
extends EditorDebuggerPlugin

var editor: VimdowEditor

var breakpoints := {}

func setup(e: VimdowEditor):
	editor = e
	editor.client.neovim_request.connect(_on_neovim_request)

func set_sesh_breakpoint(sesh: EditorDebuggerSession, buffer_name: String, line: int, enabled: bool):
	sesh.set_breakpoint(ProjectSettings.localize_path(buffer_name), line, enabled)

func _goto_script_line(script: Script, line: int) -> void:
	var path := ProjectSettings.globalize_path(script.resource_path)
	editor.open_file(path, line+1)

func _breakpoints_cleared_in_tree() -> void:
	for sesh in get_sessions():
		for buf in breakpoints:
			for line in breakpoints[buf]:
				set_sesh_breakpoint(sesh, buf, line, false)
	editor.clear_breakpoints()
	breakpoints.clear()

func _breakpoint_set_in_tree(script: Script, line: int, enabled: bool) -> void:
	var path = ProjectSettings.globalize_path(script.resource_path)
	for sesh in get_sessions():
		sesh.set_breakpoint(script.resource_path, line, enabled)
	editor.set_breakpoint(path, line + 1, enabled)

func vimdow_clear_breakpoints(buf: String) -> Variant:
	var script := load(ProjectSettings.localize_path(buf)) as Script
	var bps = breakpoints.get(buf)
	if not bps:
		return ["Buffer has no breakpoints", null]
	for line in bps:
		if bps.get(line):
			vimdow_set_breakpoint(buf, line, false)
	return [null, null]

func vimdow_set_breakpoint(buf: String, line: int, enabled: bool) -> Variant:
	if breakpoints.has(buf):
		breakpoints[buf][line] = enabled
	else:
		breakpoints[buf] = {
			line: enabled
		}
	for sesh in get_sessions():
		set_sesh_breakpoint(sesh, buf, line, enabled)
	return [null, null]

func _setup_session(session_id: int) -> void:
	var sesh = get_session(session_id)
	sesh.started.connect(_on_session_started.bind(session_id))
	sesh.stopped.connect(_on_session_stopped)
	sesh.breaked.connect(_on_session_break)

func _on_session_started(session_id: int):
	var sesh = get_session(session_id)
	for path in breakpoints:
		for line in breakpoints[path]:
			if breakpoints[path][line]:
				set_sesh_breakpoint(sesh, path, line, true)


func _on_session_stopped():
	pass

func _on_session_break(can_debug: bool):
	pass

func _on_neovim_request(msgid: int, method: String, params: Array) -> void:
	# neovim surrounds this with quotes for some reason
	method = method.lstrip('"').rstrip('"')
	if has_method(method):
		var err_and_result = callv(method, params)
		assert(err_and_result.size() == 2,
			"rpc responses need a 2 element array of [error, result]")
		editor.client.respond(msgid, err_and_result[0], err_and_result[1])
	else:
		editor.client.respond(msgid, "No method of name \"%s\" in the debugger" % method, null)
