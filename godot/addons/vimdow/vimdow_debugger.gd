class_name VimdowDebugger
extends EditorDebuggerPlugin

var editor: VimdowEditor

func _goto_script_line(script: Script, line: int) -> void:
	var path := ProjectSettings.globalize_path(script.resource_path)
	var cmd = "e +%d %s" % [line, path]
	EditorInterface.set_main_screen_editor("Vimdow")
	editor.client.request("nvim_parse_cmd", [cmd, {}])
