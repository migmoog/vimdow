@tool
extends EditorPlugin

const MAIN_SCREEN_NAME = "Vimdow"
const EDITOR = preload("res://addons/vimdow/vimdow_editor.tscn")

var editor = null

func _enter_tree() -> void:
	editor = EDITOR.instantiate()
	EditorInterface.get_editor_main_screen().add_child(editor)
	
	EditorInterface.get_script_editor()\
		.editor_script_changed\
		.connect(_on_script_changed)
	
	editor.call_deferred("start")
	_make_visible(false)


func _exit_tree() -> void:
	if editor:
		editor.queue_free()

func _on_script_changed(script: Script):
	EditorInterface.set_main_screen_editor(MAIN_SCREEN_NAME)
	editor.open_file(ProjectSettings.globalize_path(script.resource_path))

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if editor:
		editor.visible = visible

func _get_plugin_name() -> String:
	return MAIN_SCREEN_NAME
