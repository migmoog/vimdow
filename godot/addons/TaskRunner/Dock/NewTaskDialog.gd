@tool
extends Window
class_name TRNewTaskDialog

static var DEFAULT_TASK_FOLDER_KEY: String = "task_runner/default_task_folder"
static var DEFAULT_TASK_FOLDER: String = "res://"

var dock: TRTaskRunnerDock
var task_type_options: Dictionary[int, TRTaskRunner.TaskType] = {}

signal on_task_created(task: TRTask)

var _file_select_dialog_open: bool = false

@onready var row_labels: Array[Label] = [%TaskNameLabel, %TaskTypeLabel, %TaskSourceLabel, %TaskFolderLabel, %TaskFileNameLabel]

func _input(event: InputEvent) -> void:
	if not has_focus(): return
	if event.is_action_pressed("ui_cancel"):
		close_requested.emit()
	if event.is_action_pressed("ui_text_submit"):
		create_task()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not dock: return
	
	
	%TaskNameEdit.text = dock.runner.unique_task_name()
	%TaskNameEdit.text_changed.connect(func(new_text: String):
		%TaskFileNameEdit.text = _task_name_to_filename(new_text)
		_update_task_file_extension()
		%CreateButton.disabled = new_text == ""
	)
	%TaskFileNameEdit.text = _task_name_to_filename(%TaskNameEdit.text)
	%TaskNameEdit.grab_focus()
	
	%TaskFolderEdit.text = TRUtils.get_project_setting(DEFAULT_TASK_FOLDER_KEY, DEFAULT_TASK_FOLDER)

	
	# Ensure all the row labels have the same width
	var max_len = row_labels.reduce(func(p_max, row): return max(p_max, row.size.x), 0)
	row_labels.map(func(r: Label): r.custom_minimum_size.x = max_len)
	
	var id = 0
	for type in dock.runner.task_types.values():
		if type.hidden: continue
		task_type_options[id] = type
		%TaskTypeOption.add_item(type.friendly_name(), id)
		id += 1
	
	match OS.get_name():
		"Windows":
			%TaskTypeOption.select(%TaskTypeOption.get_item_index(get_task_type_id("POWERSHELL")))
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			%TaskTypeOption.select(%TaskTypeOption.get_item_index(get_task_type_id("BASH")))
		_:
			# Safe default for weirder environments like web, android, apple products
			%TaskTypeOption.select(%TaskTypeOption.get_item_index(get_task_type_id("IN_EDITOR_GDSCRIPT")))
	
	%TaskSourceOption.item_selected.connect(func(idx: int):
		update_path_state()
	)
	update_path_state()
	
	%TaskTypeOption.item_selected.connect(func(i):
		_update_task_file_extension()
	)
	_update_task_file_extension()
	
	%SelectTaskFolder.pressed.connect(func():
		_file_select_dialog_open = true
		var file_dialog = TRUtils.create_file_task_dialog(self, FileDialog.FileMode.FILE_MODE_OPEN_DIR, %TaskFolderEdit.text)
		if not file_dialog: return false

		file_dialog.dir_selected.connect(func(file_path: String):
			%TaskFolderEdit.text = file_path
		)
	)
	
	%CreateButton.pressed.connect(func():
		create_task()
	)
	
	%CancelButton.pressed.connect(func():
		if TRUtils._file_task_dialog_open: return
		close_requested.emit()
	)
	
	var bg_panel: StyleBoxFlat = %PanelContainer.get_theme_stylebox("panel")
	bg_panel.bg_color = get_theme_color("base_color", "Editor")
	%PanelContainer.add_theme_stylebox_override("panel", bg_panel)

func create_task():
	if TRUtils._file_task_dialog_open: return
	var task_type: TRTaskRunner.TaskType = current_task_type()
	var task_source: TRTask.TaskSource = TRTask.TaskSource.INLINE if %TaskSourceOption.selected == 0 else TRTask.TaskSource.ON_DISK
	
	var file_path = %TaskFolderEdit.text.path_join(%TaskFileNameEdit.text)
	
	var task = TRTask.new()
	task.task_name = %TaskNameEdit.text
	task.task_type = task_type.type_name
	task.task_source = task_source
	task._task_command = task_type.sample_script if task_source == TRTask.TaskSource.INLINE else ""
	task._task_filepath = file_path if task_source == TRTask.TaskSource.ON_DISK else ""
	task._task_callable = func(): pass
	
	if task_source == TRTask.TaskSource.ON_DISK:
		# whatever folder we used becomes the new default
		TRUtils.set_project_setting(DEFAULT_TASK_FOLDER_KEY, %TaskFolderEdit.text)
		
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		file.store_string(task_type.sample_script)
		file.close()
		EditorInterface.get_resource_filesystem().scan()
	
	on_task_created.emit(task)
	close_requested.emit()

func get_task_type_id(task_type_name: String):
	for id in task_type_options:
		if task_type_options[id].type_name == task_type_name:
			return id
	return 0

func update_path_state():
	if %TaskSourceOption.selected == 0:
		%SelectTaskFolder.disabled = true
		%TaskFileNameEdit.editable = false
		%TaskFolderEdit.editable = false
		%TaskFileNameEdit.selecting_enabled = false
		%TaskFolderEdit.selecting_enabled = false
		%TaskFileNameEdit.modulate = Color(0.85,0.85,0.85) # grey out the fields just a little (it's really lerping towards black, but decent enough hack as long as you don't go too dark)
		%TaskFolderEdit.modulate = Color(0.85,0.85,0.85)
		%TaskFileNameEdit.focus_mode = Control.FocusMode.FOCUS_NONE
		%SelectTaskFolder.focus_mode = Control.FocusMode.FOCUS_NONE
		%TaskFolderEdit.focus_mode = Control.FocusMode.FOCUS_NONE
	else:
		%SelectTaskFolder.disabled = false
		%TaskFileNameEdit.editable = true
		%TaskFolderEdit.editable = true
		%TaskFileNameEdit.selecting_enabled = true
		%TaskFolderEdit.selecting_enabled = true
		%TaskFileNameEdit.modulate = Color.WHITE
		%TaskFolderEdit.modulate = Color.WHITE
		%TaskFolderEdit.selecting_enabled = true
		%TaskFileNameEdit.focus_mode = Control.FocusMode.FOCUS_ALL
		%SelectTaskFolder.focus_mode = Control.FocusMode.FOCUS_ALL
		%TaskFolderEdit.focus_mode = Control.FocusMode.FOCUS_ALL
		
func _task_name_to_filename(task_name: String):
	task_name = task_name.to_lower()

	var cleanup_string = RegEx.new()
	cleanup_string.compile("[^a-z0-9]+")
	task_name = cleanup_string.sub(task_name, "_", true)
	
	task_name = task_name.strip_edges().trim_prefix("_").trim_suffix("_")

	return task_name

func _update_task_file_extension():
	var parts: PackedStringArray = %TaskFileNameEdit.text.split(".")
	var current_file: String = ""
	if parts.size() < 2:
		current_file = %TaskFileNameEdit.text
	else:
		current_file = ".".join(parts.slice(0, -1))
	
	%TaskFileNameEdit.text = current_file + "." + current_task_type().type_extensions[0]

func current_task_type() ->TRTaskRunner.TaskType:
	return task_type_options[%TaskTypeOption.get_item_id(%TaskTypeOption.selected)]
	
