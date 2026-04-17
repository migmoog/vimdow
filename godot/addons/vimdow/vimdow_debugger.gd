@tool
class_name VimdowDebugger
extends EditorDebuggerPlugin

var editor: VimdowEditor

var plugin_breakpoints := {}

func setup(e: VimdowEditor):
	editor = e
	editor.client.neovim_request.connect(_on_neovim_request)

func _goto_script_line(script: Script, line: int) -> void:
	var path := ProjectSettings.globalize_path(script.resource_path)
	var cmd = "e +%d %s" % [line+1, path]
	EditorInterface.set_main_screen_editor("Vimdow")
	# NOTE: nvim_command is deprecated but it's simpler than nvim_parse_cmd -> nvim_cmd
	editor.client.request("nvim_command", [cmd])

func vimdow_set_breakpoint(buf: String, line: int) -> Variant:
	print("Getting called~")
	return [null, null]

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
