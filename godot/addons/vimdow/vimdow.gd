@tool
extends EditorPlugin

const MAIN_SCREEN_NAME = "Vimdow"
const EDITOR = preload("res://addons/vimdow/vimdow_editor.tscn")

var editor: VimdowEditor
var dock: EditorDock

var debugger: VimdowDebugger

var pop_out_shortcut: Shortcut
var focus_shortcut: Shortcut

const DEFAULT_SETTINGS = { "auto_open_root_script": true, "auto_focus_on_scene_change": true }


func _enter_tree() -> void:
	if DisplayServer.get_name() == "headless": # CI/CD sanity check
		print_debug("Skipping plugin initilization")
		return

	var editor_settings := EditorInterface.get_editor_settings()
	for setting in DEFAULT_SETTINGS:
		var full_setting = "vimdow/" + setting
		if not editor_settings.has_setting(full_setting):
			editor_settings.set_setting(full_setting, DEFAULT_SETTINGS[setting])
		editor_settings.set_initial_value(full_setting, DEFAULT_SETTINGS[setting], false)

	dock = EditorDock.new()
	dock.available_layouts = EditorDock.DOCK_LAYOUT_MAIN_SCREEN | EditorDock.DOCK_LAYOUT_FLOATING
	dock.default_slot = EditorDock.DOCK_SLOT_MAIN_SCREEN
	dock.dock_icon = preload("res://addons/vimdow/images/vimdow_icon.png")
	dock.title = MAIN_SCREEN_NAME

	editor = EDITOR.instantiate()
	editor.conf_path = "res://addons/vimdow/local.cfg"
	dock.add_child(editor)
	add_dock(dock)
	editor.client.neovim_request.connect(_on_neovim_request)
	editor.call_deferred("start", PackedStringArray(["-S", "addons/vimdow/lua/start.lua"]))

	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)

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

	scene_changed.connect(_on_scene_changed)

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
	if m.begins_with("EditorInterface:"):
		var ei_method = m.trim_prefix("EditorInterface:")
		if EditorInterface.has_method(ei_method):
			editor.client.respond(
				msgid,
				null,
				{ return_value = EditorInterface.callv(ei_method, params) },
			)
		else:
			editor.client.respond(msgid, "EditorInterface does not have a method called: %s", null)


func _exit_tree() -> void:
	if debugger:
		remove_debugger_plugin(debugger)
	if editor:
		editor.client.kill_process()
	remove_dock(dock)
	dock.queue_free()
	dock = null
	editor = null
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)


func _input(event: InputEvent) -> void:
	if event.is_pressed() and focus_shortcut.matches_event(event):
		get_viewport().set_input_as_handled()
		EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
		return


func _on_scene_changed(scene_root: Node) -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	if not editor_settings.get_setting("vimdow/auto_open_root_script"):
		return
	if scene_root == null:
		return
	var script = scene_root.get_script()
	if script and script.resource_path.begins_with("res://"):
		editor.open_file(ProjectSettings.globalize_path(script.resource_path))
		if editor_settings.get_setting("vimdow/auto_focus_on_scene_change"):
			editor.grab_focus()


func _handles(object: Object) -> bool:
	return [&"Script", &"TextFile", &"GDExtension", &"JSON"].any(
		func(c):
			return ClassDB.is_parent_class(object.get_class(), c),
	)


func _edit(object: Object):
	if object == null:
		return

	editor.open_file(ProjectSettings.globalize_path(object.resource_path))
	editor.grab_focus()


func _make_visible(visible: bool) -> void:
	if dock:
		dock.visible = visible
		editor.grab_focus()
