@tool
extends EditorPlugin

const MAIN_SCREEN_NAME = "Vimdow"
const EDITOR = preload("res://addons/vimdow/vimdow_editor.tscn")

var _last_main_screen: String = ""
var editor: VimdowEditor
var window_wrapper: Window

var debugger: VimdowDebugger

var pop_out_shortcut: Shortcut

const DEFAULT_SETTINGS = {
	"path_to_nvim" : "/usr/bin/nvim",
}

func _enter_tree() -> void:
	for setting in DEFAULT_SETTINGS:
		var full_setting = "vimdow/" + setting
		if not ProjectSettings.has_setting(full_setting):
			ProjectSettings.set_setting(full_setting, DEFAULT_SETTINGS[setting])
	
	editor = EDITOR.instantiate()
	EditorInterface.get_editor_main_screen().add_child(editor)
	editor.call_deferred("start")
	
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

	EditorInterface.get_editor_settings()\
			.add_shortcut("vimdow/pop_out_window", pop_out_shortcut)

	_make_visible(false)
	
	main_screen_changed.connect(_on_main_screen_changed)

	debugger = VimdowDebugger.new()
	# debugger.editor = editor
	debugger.setup(editor)
	add_debugger_plugin(debugger)


func _exit_tree() -> void:
	if editor:
		editor.client.kill_process()
		editor.queue_free()
	if window_wrapper:
		window_wrapper.queue_free()
	if debugger:
		remove_debugger_plugin(debugger)

func _input(event: InputEvent) -> void:
	if editor.visible \
			and event.is_pressed() \
			and  pop_out_shortcut.matches_event(event):
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
	return object is Script

func _edit(object: Object):
	if object == null:
		return
	
	editor.open_file(ProjectSettings.globalize_path(object.resource_path))
	editor.grab_focus()

func _has_main_screen() -> bool:
	return true

func _get_plugin_icon() -> Texture2D:
	return preload("res://addons/vimdow/images/vimdow_icon.png")

func _make_visible(visible: bool) -> void:
	if editor:
		editor.visible = window_wrapper.visible or visible
	if window_wrapper.visible:
		_focus_last_editor()
		window_wrapper.show()
		editor.grab_focus()

func _focus_last_editor():
	if window_wrapper.visible:
		assert(not _last_main_screen.is_empty())
		EditorInterface.get_base_control().get_viewport().gui_release_focus()
		EditorInterface.set_main_screen_editor(_last_main_screen)

func _get_plugin_name() -> String:
	return MAIN_SCREEN_NAME
