@tool
extends EditorPlugin

const MAIN_SCREEN_NAME = "Vimdow"
const EDITOR = preload("res://addons/vimdow/vimdow_editor.tscn")

var _last_main_screen: String = ""
var editor: VimdowEditor
var builtin_scripts := { }
var window_wrapper: Window

var debugger: VimdowDebugger

var pop_out_shortcut: Shortcut
var focus_shortcut: Shortcut

const DEFAULT_SETTINGS = { }


func _enter_tree() -> void:
	if DisplayServer.get_name() == "headless": # CI/CD sanity check
		print_debug("Skipping plugin initilization")
		return

	for setting in DEFAULT_SETTINGS:
		var full_setting = "vimdow/" + setting
		if not ProjectSettings.has_setting(full_setting):
			ProjectSettings.set_setting(full_setting, DEFAULT_SETTINGS[setting])
		ProjectSettings.set_initial_value(full_setting, DEFAULT_SETTINGS[setting])

	editor = EDITOR.instantiate()
	editor.conf_path = "res://addons/vimdow/local.cfg"
	EditorInterface.get_editor_main_screen().add_child(editor)
	editor.client.neovim_request.connect(_on_neovim_request)
	editor.call_deferred("start", PackedStringArray(["-S", "addons/vimdow/lua/start.lua"]))

	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)

	window_wrapper = Window.new()
	add_child(window_wrapper)
	window_wrapper.hide()
	window_wrapper.close_requested.connect(_on_editor_window_close)

	pop_out_shortcut = Shortcut.new()
	var poev = InputEventKey.new()
	poev.pressed = true
	poev.ctrl_pressed = true
	poev.shift_pressed = true
	poev.keycode = KEY_SPACE
	pop_out_shortcut.events = [poev]

	EditorInterface.get_editor_settings() \
			.add_shortcut("vimdow/pop_out_window", pop_out_shortcut)

	focus_shortcut = Shortcut.new()
	var fev = InputEventKey.new()
	fev.pressed = true
	fev.ctrl_pressed = true
	fev.alt_pressed = true
	fev.keycode = KEY_V
	focus_shortcut.events = [fev]

	EditorInterface.get_editor_settings() \
			.add_shortcut("vimdow/focus", focus_shortcut)

	_make_visible(false)

	main_screen_changed.connect(_on_main_screen_changed)

	debugger = VimdowDebugger.new()
	debugger.setup(editor)
	add_debugger_plugin(debugger)


func _on_gui_focus_changed(control: Control):
	# Script editor steals focus when making edits to an already existing script
	# so the VimdowEditor needs to steal it back
	var se := EditorInterface.get_script_editor()
	if editor.visible and se.is_ancestor_of(control):
		editor.grab_focus()


func _on_neovim_request(msgid: int, method: String, params: Array):
	var m := method.lstrip('"').rstrip('"')
	if has_method(m):
		var res = callv(m, params)
		editor.client.respond(msgid, res.err, res.val)
	elif m.begins_with("EditorInterface:"):
		var ei_method = m.trim_prefix("EditorInterface:")
		if EditorInterface.has_method(ei_method):
			editor.client.respond(
				msgid,
				null,
				{ return_value = EditorInterface.callv(ei_method, params) },
			)
		else:
			editor.client.respond(msgid, "EditorInterface does not have a method called: %s", null)


## Called via RPC to save a builtin script from a special buffer
func save_builtin_script(resource_path: String, source_code: String) -> Dictionary:
	var out = { val = null, err = null }
	var packed_scene = resource_path.get_slice("::", 0)
	var dict = builtin_scripts.get(packed_scene)
	if not dict:
		out.err = "Vimdow doesn't hold a ref to anything in PackedScene %s" % packed_scene
	var scr = dict.get(resource_path.get_slice("::", 1))
	if not scr:
		out.err = "Vimdow doesn't hold a ref to '%s' to save" % resource_path
		return out
	scr.source_code = source_code
	var ps = ResourceLoader.load(packed_scene, "", ResourceLoader.CACHE_MODE_REUSE)
	var res = ResourceSaver.save(ps, packed_scene)

	if res != OK:
		out.err = "Couldn't save builtin script: '%s'" % error_string(res)

	return out


func close_builtin_script(resource_path: String) -> Dictionary:
	var out = { val = null, err = null }
	var packed_scene = resource_path.get_slice("::", 0)
	var subres_id = resource_path.get_slice("::", 1)
	var dict = builtin_scripts.get(resource_path)
	if not dict:
		out.err = "Vimdow doesn't hold a ref to builtin scripts of PackedScene %s" % packed_scene
		return out
	if not dict.erase(subres_id):
		out.err = "Vimdow doesn't hold a ref to %s" % resource_path
	return out


func _exit_tree() -> void:
	if editor:
		editor.client.kill_process()
		editor.queue_free()
	if window_wrapper:
		window_wrapper.queue_free()
	if debugger:
		remove_debugger_plugin(debugger)


func _input(event: InputEvent) -> void:
	if event.is_pressed() and focus_shortcut.matches_event(event):
		get_viewport().set_input_as_handled()
		EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
		return

	if editor.visible \
			and event.is_pressed() \
			and pop_out_shortcut.matches_event(event):
		get_viewport().set_input_as_handled()
		var ms := EditorInterface.get_editor_main_screen()
		if not window_wrapper.visible:
			window_wrapper.show()
			ms.remove_child(editor)
			window_wrapper.add_child(editor)
			editor.lock_to_window(window_wrapper)
			editor.grab_focus()


func _on_editor_window_close():
	editor.unlock_from_window()
	window_wrapper.remove_child(editor)
	window_wrapper.hide()

	EditorInterface.get_editor_main_screen().add_child(editor)
	EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)


func _on_main_screen_changed(screen_name: String):
	if screen_name != _get_plugin_name():
		_last_main_screen = screen_name


func _handles(object: Object) -> bool:
	if editor and editor.conf.get_value(editor.MAIN_SECTION, "template", false):
		return false

	return [&"Script", &"TextFile", &"GDExtension", &"JSON"].any(
		func(c):
			return ClassDB.is_parent_class(object.get_class(), c),
	)


func _edit(object: Object):
	if object == null:
		return

	var global_path = object.resource_path
	if object is Script:
		var scr := object as Script
		const DOUBLE_COLON = "::"
		var double_colon_idx = scr.resource_path.rfind(DOUBLE_COLON)
		# script is builtin
		if double_colon_idx != -1:
			# var packed_scene_path = scr.resource_path.get_slice("::", 0)
			var path_info = scr.resource_path.rsplit(DOUBLE_COLON)
			assert(path_info.size() == 2)
			var packed_scene_path = path_info[0]
			var subres_id = path_info[1]
			var scene_dict := builtin_scripts.get_or_add(packed_scene_path, {})
			scene_dict.set(subres_id, scr)
			editor.open_builtin_script(scr.resource_path, scr.source_code)
		else:
			editor.open_file(global_path)
	else:
		editor.open_file(ProjectSettings.globalize_path(object.resource_path))
	editor.grab_focus()


func _has_main_screen() -> bool:
	return true


func _get_plugin_icon() -> Texture2D:
	return preload("res://addons/vimdow/images/vimdow_icon.png")


func _make_visible(visible: bool) -> void:
	if editor:
		editor.visible = window_wrapper.visible or visible
	if window_wrapper and window_wrapper.visible:
		_focus_last_editor()
		window_wrapper.show()
	if visible:
		editor.grab_focus()


func _focus_last_editor():
	if window_wrapper.visible:
		assert(not _last_main_screen.is_empty())
		EditorInterface.get_base_control().get_viewport().gui_release_focus()
		EditorInterface.set_main_screen_editor(_last_main_screen)


func _get_plugin_name() -> String:
	return MAIN_SCREEN_NAME
