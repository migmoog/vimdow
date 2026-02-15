@tool
extends VBoxContainer

signal on_task_created(task: TRTask)
signal on_task_updated(task: TRTask)

var dock: TRTaskRunnerDock
var current_task: TRTask

func _ready():
	%OpenFileInEditorButton.pressed.connect(_open_current_task_in_editor)
	
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(func():
		update_file_missing_warning()
	)
	update_file_missing_warning()

var current_dialog: TRNewTaskDialog
func create_task():
	if current_dialog:
		current_dialog.grab_focus()
		return
	
	current_dialog = preload("res://addons/TaskRunner/Dock/NewTaskDialog.tscn").instantiate()
	current_dialog.dock = dock
	current_dialog.popup_exclusive(get_window())
	current_dialog.on_task_created.connect(func(task: TRTask):
		on_task_created.emit(task)
	)
	current_dialog.close_requested.connect(func():
		if current_dialog:
			current_dialog.queue_free()
			current_dialog = null
	)

func import_task() -> bool:
	var file_dialog = TRUtils.create_file_task_dialog(get_window(), FileDialog.FILE_MODE_OPEN_FILE)
	if not file_dialog: return false

	file_dialog.file_selected.connect(func(file_path: String):
		# Infer the task type from the list of known extensions.
		var task_type: TRTaskRunner.TaskType = dock.runner.file_task_type_with_defaults(file_path)
		on_task_created.emit(TRTask.new_on_disk(task_type.type_name, file_path.split("res://")[1], file_path))
	)

	return true

func select_task(task: TRTask):
	current_task = task
	update_file_missing_warning()
	
	# Clear connections to the select file button first
	for conn in %SelectFileButton.pressed.get_connections():
		%SelectFileButton.pressed.disconnect(conn.callable)

	%FileNameLabel.text = task.get_task_filepath()
	%SelectFileButton.pressed.connect(func():
		var file_dialog := TRUtils.create_file_task_dialog(get_window(), FileDialog.FILE_MODE_OPEN_FILE, task.get_task_filepath())
		if not file_dialog: return
		file_dialog.file_selected.connect(func(file_path: String):
			if ("res://" + task.task_name) == task.get_task_filepath():
				# If the name was the default name, update it, otherwise leave it alone
				task.task_name = file_path.split("res://")[1]
			var task_type: TRTaskRunner.TaskType = dock.runner.file_task_type_with_defaults(file_path)
			task.task_type = task_type.type_name
			task.set_task_filepath(file_path)
			on_task_updated.emit(task)
		)
	)

func _open_current_task_in_editor():
	update_file_missing_warning()
	var full_path = current_task.get_task_filepath()
	if not FileAccess.file_exists(full_path):
		push_error("Task file missing: " + full_path)
		return
	
	# Classic godot insanity. The ResourceLoader doesn't know how to open a .txt file (or .sh, or any other type of file)
	# BUT, the FileSystemDock knows how to, so we automate the UI, navigate to the task, and activate it in the UI. Weird, but works, I guess

	# find the file tree within the FileSystemDock
	var file_tree: Tree
	for t in EditorInterface.get_file_system_dock().find_children("*", "Tree", true, false ):
		if t.get_root() and t.get_root().get_children().any(func(c): return c.get_text(0) == "res://"):
			file_tree = t
			break
	
	# Focus our script in the file tree
	EditorInterface.get_file_system_dock().navigate_to_path(full_path)
	if file_tree and file_tree.get_selected():
		file_tree.item_activated.emit()


func update_file_missing_warning():
	if current_task == null or FileAccess.file_exists(current_task.get_task_filepath()):
		%FileMissingWarning.visible = false
	else:
		%FileMissingWarning.visible = true
