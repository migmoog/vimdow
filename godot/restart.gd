# This script is mainly for restarting changes to stuff in the Godot part of the plugin
# changes to the rust section crashes the editor on reload.

@tool
extends EditorScript

# no _process loop :-(
const WAIT_FRAMES = 100

func _run() -> void:
	if EditorInterface.is_plugin_enabled("vimdow"):
		print("Turning off plugin")
		EditorInterface.set_plugin_enabled("vimdow", false)
		var i = 0
		print("Waiting to reactivate plugin")
		while i < WAIT_FRAMES:
			i += 1
	print("Turning plugin on")
	EditorInterface.set_plugin_enabled("vimdow", true)
	EditorInterface.set_main_screen_editor("Vimdow")
