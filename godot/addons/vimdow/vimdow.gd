@tool
extends EditorPlugin

const EDITOR = preload("res://addons/vimdow/vimdow_editor.tscn")

var editor = null

func _enter_tree() -> void:
	editor = EDITOR.instantiate()
	EditorInterface.get_editor_main_screen().add_child(editor)
	_make_visible(false)


func _exit_tree() -> void:
	if editor:
		editor.queue_free()

func _has_main_screen() -> bool:
	return true

func _make_visible(visible: bool) -> void:
	if editor:
		editor.visible = visible
		if not editor.attached and visible:
			editor.call_deferred("start")

func _get_plugin_name() -> String:
	return "Vimdow"
