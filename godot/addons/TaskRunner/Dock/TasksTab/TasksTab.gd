@tool
extends TRDockTab
class_name TRTasksTab

var task_tree_root: TreeItem
var task_tree_items: Dictionary[TRTask, TreeItem] = {}
var previously_focused_task: TRTask = null
var task_type_indexes: Dictionary[String, int]

@onready var select_task_buttons: Tree = side_panel.get_node("%SelectTaskButtons")
@onready var run_task_button: Button = footer.get_node("%RunTaskButton")
@onready var inline_task_editor: CodeEdit = get_node("%InlineTaskEditor")
@onready var file_task_editor: VBoxContainer = get_node("%FileTaskEditor")
@onready var onboarding_panel: Control = get_node("%OnboardingPanel")
@onready var task_editor: VBoxContainer = get_node("%TaskEditor")
@onready var set_task_type_option: OptionButton = footer.get_node("%SetTaskTypeOption")
@onready var new_task_button: MenuButton = side_panel.get_node("%NewTaskButton")
@onready var current_task_name_label: Label = footer.get_node("%CurrentTaskNameLabel")

func _init() -> void:
	tab_name = "Task Editor"
	footer = preload("res://addons/TaskRunner/Dock/TasksTab/Footer.tscn").instantiate()
	side_panel = preload("res://addons/TaskRunner/Dock/TasksTab/SidePanel.tscn").instantiate()

func _ready() -> void:
	if not runner: return
	
	inline_task_editor.hide()
	file_task_editor.hide()
	update_onboarding_panel()
	
	file_task_editor.dock = dock
	onboarding_panel.runner = dock.runner
	
	select_task_buttons.set_column_title(0, "Tasks")
	task_tree_root = select_task_buttons.create_item()

	select_task_buttons.item_selected.connect(func():
		var current_task = get_current_task()
		if not current_task:
			_clear_focused_task()
		else:
			focus_task(current_task)
	)
	
	runner.on_task_type_added.connect(func():
		_populate_task_types_list()
	)
	_populate_task_types_list()
	
	runner.on_task_added.connect(func(task: TRTask):
		_add_task(task)
	)
	for task in runner.tasks:
		_add_task(task)
	
	runner.on_tasks_reordered.connect(func():
		# remove all the tree nodes and re-add them all
		# then select the one that was already selected
		
		var currently_focused: TRTask = select_task_buttons.get_selected().get_metadata(0)
		
		for item in task_tree_items:
			task_tree_root.remove_child(task_tree_items[item])
			
		task_tree_items.clear()
		
		for task in runner.tasks:
			task_tree_items[task] = select_task_buttons.create_item(task_tree_root)
			task_tree_items[task].set_text(0, task.task_name)
			task_tree_items[task].set_metadata(0, task)
			if task == currently_focused:
				task_tree_items[task].select(0)
		
	)

	run_task_button.pressed.connect(func():
		_run_current_task()
	)

	inline_task_editor.text_changed.connect(func():
		get_current_task().set_task_command(inline_task_editor.text)
	)
	
	set_task_type_option.item_selected.connect(func(idx):
		for type in task_type_indexes:
			if task_type_indexes[type] == idx:
				get_current_task().task_type = type
	)

	select_task_buttons.item_mouse_selected.connect(func(mouse_position: Vector2, mouse_button_index: int):
		if mouse_button_index != MOUSE_BUTTON_RIGHT:
			return
		
		TRUtils.simple_popup_menu({
			"Run": func():
		
				_run_current_task(),
			"Rename": func():
				select_task_buttons.edit_selected(true),
			"Delete": func():
				_delete_current_task(),
			"Move Up": func():
				runner.move_task(get_current_task_name(), -1),
			"Move Down": func():
				runner.move_task(get_current_task_name(), 1)
		})
	)
	
	select_task_buttons.item_edited.connect(func():
		var current_task = get_current_task()
		var current_item = task_tree_items[current_task]
		current_task.task_name = current_item.get_text(0)
		save_current_task()
	)
	
	new_task_button.get_popup().id_pressed.connect(func(id: int):
		match id:
			0:
				file_task_editor.create_task()
			1:
				file_task_editor.import_task()
	)
	
	new_task_button.pressed.connect(func():
		new_task_button.get_popup().position = DisplayServer.mouse_get_position()
	)

	file_task_editor.on_task_created.connect(runner.add_task)
	file_task_editor.on_task_updated.connect(func(task: TRTask):
		save_task(task)
		focus_task(task)
	)

	runner.on_task_updated.connect(func(task: TRTask):
		# delete the old one
		# add the new one in it's place
		if task_tree_items.has(task):
			var current_tree_item: TreeItem = task_tree_items[task]
			current_tree_item.set_text(0, task.task_name)
			current_tree_item.set_metadata(0, task)
	)

	runner.on_task_removed.connect(func(to_erase: TRTask):
		var to_erase_idx: int = 0
		for item in task_tree_items.keys():
			if to_erase == item:
				break
			to_erase_idx += 1
				
		task_tree_root.remove_child(task_tree_items[to_erase])
		task_tree_items.erase(to_erase)
		var item_count = task_tree_items.values().size()
		if item_count > 0:
			focus_task(task_tree_items.keys()[min(item_count - 1, to_erase_idx)])
		else:
			_clear_focused_task()
		
		update_onboarding_panel()
	)
	
	on_hidden.connect(func():
		save_current_task()
	)
	
func _add_task(task: TRTask):
	task_tree_items[task] = select_task_buttons.create_item(task_tree_root)
	task_tree_items[task].set_text(0, task.task_name)
	task_tree_items[task].set_metadata(0, task)
	
	focus_task(task)
	update_onboarding_panel()

func has_task(task: TRTask):
	return task_tree_items.has(task)

func focus_task(task: TRTask):
	if previously_focused_task:
		if previously_focused_task.task_name != task.task_name:
			save_task(previously_focused_task)
			
	var changed_tasks = previously_focused_task != task
	previously_focused_task = task
	
	var current_task = get_current_task()
	if current_task and current_task.task_name != task.task_name:
		save_current_task() # save the old task
	
	if changed_tasks:
		set_task_type_option.select(task_type_indexes[task.task_type])
	
	current_task_name_label.text = task.get_task_filepath()

	match task.task_source:
		TRTask.TaskSource.INLINE:
			file_task_editor.hide()
			inline_task_editor.show()
			inline_task_editor.text = task.get_task_command()
		TRTask.TaskSource.ON_DISK:
			file_task_editor.show()
			inline_task_editor.hide()
			file_task_editor.select_task(task)
		_:
			push_error("Showing a task editor, but there is not editor for task type: " + TRTask.TaskSource.keys()[task.task_source])

	# focus this row
	if changed_tasks and task_tree_items.has(task):
		task_tree_items[task].select(0)
		select_task_buttons.scroll_to_item(task_tree_items[task])
		
	
func _clear_focused_task():
	focus_task(TRTask.new_inline("BASH", "", ""))

func _run_current_task():
	save_current_task()
	var r: TRTaskRun = runner.execute_run(get_current_task_name())
	dock.task_run_tab.activate_run(r)

func save_current_task():
	save_task(get_current_task())

func save_task(task: TRTask):
	if not task: return
	runner.update_task(task)
	
func get_current_task_name():
	var selected_item = select_task_buttons.get_selected()
	if not selected_item:
		return ""
	return selected_item.get_metadata(0).task_name
	
func get_current_task():
	var current_task_name = get_current_task_name()
	if current_task_name == "":
		return null
	return runner.get_task(current_task_name)


func _populate_task_types_list():
	set_task_type_option.clear()
	task_type_indexes.clear()
	var idx = 0
	for task_type in TRTaskRunner.get_singleton().task_types.values():
		if task_type.hidden: continue
		task_type_indexes[task_type.type_name] = idx
		set_task_type_option.add_item(task_type.friendly_name(), idx)
		idx += 1
	
var _delete_task_open: bool = false
func _delete_current_task():
	if _delete_task_open: return
	_delete_task_open = true
	var task_to_delete = get_current_task().task_name
	var confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Confirm Delete Task"
	confirm_dialog.ok_button_text = "Delete"
	confirm_dialog.cancel_button_text = "Do Not Delete"
	confirm_dialog.dialog_text = "Delete '%s' task?" % task_to_delete
	confirm_dialog.confirmed.connect(func():
		_delete_task_open = false
		runner.remove_task(task_to_delete)
	)
	confirm_dialog.canceled.connect(func():
		_delete_task_open = false
		dock.task_run_tab.update_task_run_tree() # I don't remember why I added this... seems unnessessary
	)
	add_child(confirm_dialog)
	confirm_dialog.popup_centered()

func update_onboarding_panel():
	if runner.tasks.size() == 0:
		onboarding_panel.visible = true
		task_editor.visible = false
	else:
		onboarding_panel.visible = false
		task_editor.visible = true
		
