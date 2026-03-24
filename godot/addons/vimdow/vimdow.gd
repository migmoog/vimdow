@tool
extends EditorPlugin

const MAIN_SCREEN_NAME = "Vimdow"
const EDITOR = preload("res://addons/vimdow/vimdow_editor.tscn")

var editor: VimdowEditor
var editor_window: Window

var pop_out_shortcut: Shortcut

func _enter_tree() -> void:
	if not ProjectSettings.has_setting("vimdow/path_to_nvim"):
		ProjectSettings.set_setting("vimdow/path_to_nvim", "/usr/bin/nvim")
	
	editor = EDITOR.instantiate()
	EditorInterface.get_editor_main_screen().add_child(editor)
	
	editor.call_deferred("start")
	
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


func _exit_tree() -> void:
	if editor:
		editor.client.kill_process()
		editor.queue_free()
	if editor_window:
		editor_window.queue_free()

func _input(event: InputEvent) -> void:
	if editor.visible and event.is_pressed() and  pop_out_shortcut.matches_event(event):
		get_viewport().set_input_as_handled()
		var ms := EditorInterface.get_editor_main_screen()
		if editor_window:
			editor_window.close_requested.emit()
		else:
			editor_window = Window.new()
			EditorInterface.get_base_control().add_child(editor_window)
			ms.remove_child(editor)
			editor_window.add_child(editor)
			editor.lock_to_window(editor_window)
			editor_window.close_requested.connect(_on_editor_window_close)

func _on_editor_window_close():
	editor.unlock_from_window()
	editor_window.remove_child(editor)
	editor_window.queue_free()
	editor_window = null
	
	EditorInterface.get_editor_main_screen().add_child(editor)

func _handles(object: Object) -> bool:
	return object is Script

func _edit(object: Object):
	if object == null:
		return
	
	EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
	editor.open_file(ProjectSettings.globalize_path(object.resource_path))

func _has_main_screen() -> bool:
	return true

func _get_plugin_icon() -> Texture2D:
	return preload("res://addons/vimdow/images/vimdow_icon.png")

func _make_visible(visible: bool) -> void:
	if editor:
		editor.visible = visible

func _get_plugin_name() -> String:
	return MAIN_SCREEN_NAME
