@tool
extends TRDockTab
class_name TRTaskRunsTab

# UI Element Bindings
@onready var task_runs_list: Tree = side_panel.get_node("%TaskRunsList")
@onready var run_state: Label = footer.get_node("%RunState")
@onready var run_start_time: Label = footer.get_node("%RunStartTime")
@onready var run_end_time: Label = footer.get_node("%RunEndTime")
@onready var run_exit_status: Label = footer.get_node("%RunExitStatus")
@onready var task_run_logs: CodeEdit = get_node("%TaskRunLogs")
@onready var task_run_messages: CodeEdit = get_node("%TaskRunMessages")
@onready var show_task_button: Button = footer.get_node("%ShowTaskButton")
@onready var cancel_rerun_button: Button = footer.get_node("%CancelRerunButton")
@onready var messages_container: VBoxContainer = get_node("%MessagesContainer")
@onready var logs_container: VBoxContainer = get_node("%LogsContainer")
@onready var logs_header: Label = get_node("%LogsHeader")
@onready var messages_header: Label = get_node("%MessagesHeader")

# Class State
var run_tree_items: Dictionary[TRTaskRun, TreeItem] = {}
var previously_focused_run: TRTaskRun = null
var previously_focused_run_listeners: Dictionary = {}

func _init() -> void:
	tab_name = "Task Runs"
	footer = preload("res://addons/TaskRunner/Dock/TaskRunsTab/Footer.tscn").instantiate()
	side_panel = preload("res://addons/TaskRunner/Dock/TaskRunsTab/SidePanel.tscn").instantiate()

var _delete_run_open: bool = false
func _ready() -> void:
	if not runner: return
	
	task_runs_list.set_column_title(0, "Task Runs")
	
	task_runs_list.item_selected.connect(func():
		activate_run(get_current_task_run())
	)
	
	task_runs_list.item_mouse_selected.connect(func(mouse_position: Vector2, mouse_button_index: int):
		if mouse_button_index != MOUSE_BUTTON_RIGHT:
			return
		
		TRUtils.simple_popup_menu({
			"Show Task": func():
				show_current_task(),
			"Rename": func():
				task_runs_list.edit_selected(true),
			redo_run_label(get_current_task_run()): func():
				run_rerun_cancel_run(get_current_task_run()),
			"Delete": func():
				if _delete_run_open: return
				_delete_run_open = true
				var to_delete = get_current_task_run().get_root_task().run_name
				var confirm_dialog = ConfirmationDialog.new()
				confirm_dialog.title = "Confirm Delete Run"
				confirm_dialog.ok_button_text = "Delete"
				confirm_dialog.cancel_button_text = "Do Not Delete"
				confirm_dialog.dialog_text = "Delete '%s' run?" % to_delete
				confirm_dialog.confirmed.connect(func():
					_delete_run_open = false
					runner.delete_run(get_current_task_run())
				)
				confirm_dialog.canceled.connect(func():
					_delete_run_open = false
				)
				add_child(confirm_dialog)
				confirm_dialog.popup_centered()
		})
	)
	
	runner.on_run_added.connect(func(run: TRTaskRun):
		run.on_begin.connect(func(): update_task_run_tree())
		run.on_end.connect(func(s): update_task_run_tree())
		update_task_run_tree()
	)
	
	runner.on_run_removed.connect(func(run: TRTaskRun):
		var to_remove: TreeItem = run_tree_items[run]
		var root: TreeItem = task_runs_list.get_root()
		
		# find our current index
		var idx = 0
		for i in root.get_child_count():
			if root.get_child(i) == to_remove:
				idx = i
				break
		
		# remove this item
		root.remove_child(to_remove)
		run_tree_items.erase(run)
		
		# focus the correct item if there are any items left
		if root.get_child_count() != 0:
			activate_run(runner.task_runs[min(runner.task_runs.size()-1, idx)]) # choose the one behind us
		
	)
	
	show_task_button.pressed.connect(func():
		show_current_task()
	)
	
	cancel_rerun_button.pressed.connect(func():
		run_rerun_cancel_run(get_current_task_run())
	)

func show_current_task():
	var to_show: TRTaskRun = get_current_task_run().get_real_parent()
	if not to_show: return
	dock.set_visible_tab(dock.task_tab)
	dock.task_tab.focus_task(to_show.task)

func get_current_task_run() -> TRTaskRun:
	if not task_runs_list.get_selected(): return null
	return task_runs_list.get_selected().get_metadata(0)

func redo_run_label(run: TRTaskRun):
	match run.state:
		TRTaskRun.TaskState.NOT_STARTED:
			return "Run"
		TRTaskRun.TaskState.FINISHED:
			return "Rerun"
		TRTaskRun.TaskState.RUNNING:
			return "Cancel"
		
func run_rerun_cancel_run(run: TRTaskRun):
	if run.state == TRTaskRun.TaskState.RUNNING:
		# you can cancel an anonymous task
		run.cancel_task()
		return
	
	# but look up the real parent task if we're re-running
	var real_run: TRTaskRun = run.get_real_parent()
	if not real_run: return
	real_run.clear()
	real_run.run_task()

var logs_to_append: Array[String] = []
var messages_to_append: Array[String] = []
func _process(delta: float) -> void:
	if logs_to_append.size() > 0:
		task_run_logs.text += "\n".join(logs_to_append) + "\n"
		logs_to_append.clear()
		task_run_logs.set_v_scroll(task_run_logs.get_line_count())
		task_run_logs.set_caret_line(task_run_logs.get_line_count() - 1)
	
	if messages_to_append.size() > 0:
		task_run_messages.text += "\n".join(messages_to_append) + "\n"
		messages_to_append.clear()
		task_run_messages.set_v_scroll(task_run_messages.get_line_count())
		task_run_messages.set_caret_line(task_run_messages.get_line_count() - 1)

func activate_run(run: TRTaskRun):
	cancel_rerun_button.text = redo_run_label(run)
	
	# if the correct run is already focused, do nothing
	if run_tree_items.has(run) and run_tree_items[run] and not run_tree_items[run].is_queued_for_deletion() and not run_tree_items[run].is_selected(0):
		run_tree_items[run].select(0)
		
	if previously_focused_run == run:
		return
	
	var update_status_line = func():
		run_state.text = TRTaskRun.TaskState.keys()[run.state].to_lower().replace("_", " ")
		match run.state:
			TRTaskRun.TaskState.NOT_STARTED:
				run_start_time.text = "..."
				run_end_time.text = "..."
				run_exit_status.text = "..."
			TRTaskRun.TaskState.RUNNING:
				run_start_time.text = TRUtils.format_time(run.begin_time)
				run_end_time.text = "..."
				run_exit_status.text = "..."
			TRTaskRun.TaskState.FINISHED:
				run_start_time.text = TRUtils.format_time(run.begin_time)
				run_end_time.text = TRUtils.format_time(run.end_time)
				run_exit_status.text = run.end_status
		
	var add_log_line = func(line: TRTaskRun.LogLine):
		logs_to_append.push_back(line.log_string())
		
	var add_message_line = func(message: TRTaskRun.LogMessage):
		messages_to_append.push_back(message.log_string())
		_show_messages_pane() # if there are any messages, show the messages pane
	
	var on_run_cleared = func():
		update_status_line.call()
		task_run_logs.text = ""
		task_run_messages.text = ""
		logs_to_append.clear()
		messages_to_append.clear()
		_hide_messages_pane()
		dock.set_visible_tab(self)
		
	# populate initial data
	on_run_cleared.call()
	
	for line in run.logs:
		add_log_line.call(line)
	for message in run.messages:
		add_message_line.call(message)
	
	# clear old listeners
	if previously_focused_run:
		previously_focused_run.on_begin.disconnect(previously_focused_run_listeners.on_begin)
		previously_focused_run.on_end.disconnect(previously_focused_run_listeners.on_end)
		previously_focused_run.on_log.disconnect(previously_focused_run_listeners.on_log)
		previously_focused_run.on_message.disconnect(previously_focused_run_listeners.on_message)
		previously_focused_run.cleared.disconnect(previously_focused_run_listeners.cleared)
		
	# add new listeners
	previously_focused_run_listeners.on_begin = func(): update_status_line.call()
	previously_focused_run_listeners.on_end = func(status: String): update_status_line.call()
	previously_focused_run_listeners.on_log = add_log_line
	previously_focused_run_listeners.on_message = add_message_line
	previously_focused_run_listeners.cleared = on_run_cleared
	
	run.on_begin.connect(previously_focused_run_listeners.on_begin)
	run.on_end.connect(previously_focused_run_listeners.on_end)
	run.on_log.connect(previously_focused_run_listeners.on_log)
	run.on_message.connect(previously_focused_run_listeners.on_message)
	run.cleared.connect(previously_focused_run_listeners.cleared)
	previously_focused_run = run
	
func _show_messages_pane():
	messages_container.visible = true
	messages_header.visible = true
	logs_header.visible = true

func _hide_messages_pane():
	messages_container.visible = false
	messages_header.visible = false
	logs_header.visible = false

func update_task_run_tree():
	var selected_tree_item: TreeItem = task_runs_list.get_selected()
	var currently_selected: TRTaskRun = selected_tree_item.get_metadata(0) if selected_tree_item else null
	task_runs_list.clear()
	var add_children = { "func": null }
	add_children.func = func(parent: TreeItem, to_add: TRTaskRun):
		var item: TreeItem = parent.create_child() # 1. add ourself to our parent
		
		match to_add.state:
			TRTaskRun.TaskState.NOT_STARTED:
				item.add_button(0, preload("res://addons/TaskRunner/Icons/TileUnchecked.svg"), -1, false, "Not Started")
			TRTaskRun.TaskState.RUNNING:
				item.add_button(0, preload("res://addons/TaskRunner/Icons/Timer.svg"), -1, false, "Running")
			TRTaskRun.TaskState.FINISHED:
				item.add_button(0, preload("res://addons/TaskRunner/Icons/TileChecked.svg"), -1, false, "Finished")
		
		item.set_metadata(0, to_add) # 2. set out metadata
		item.set_text(0, to_add.run_name)
		run_tree_items[to_add] = item # 3. add entry to run_tree_items
		for child in to_add.subtask_runs: # 4. add our children to ourself
			add_children.func.call(item, child)
		
	var root: TreeItem = task_runs_list.create_item()
	for run in runner.task_runs:
		add_children.func.call(root, run)
	
	if currently_selected:
		activate_run(currently_selected)
		
