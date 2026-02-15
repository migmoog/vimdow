extends RefCounted
class_name TRTaskRun

# emit events on state changes
signal on_begin
signal on_end(status: String) # status string
signal on_log(line: LogLine) # output and error combined
signal on_message(message: LogMessage)

var cancel_requested: bool = false
signal cancel_run_requested
signal cleared

# store event data for future reference
var logs: Array[LogLine] = []
var messages: Array[LogMessage] = []
var state: TaskState
var end_status: String
var begin_time: float = 0
var end_time: float = 0

var run_name: String
var parent_run: TRTaskRun
var subtask_runs: Array[TRTaskRun] = []
var task: TRTask
var task_runner: TRTaskRunner

func _init(p_run_name: String, p_task: TRTask, p_task_runner: TRTaskRunner):
	run_name = p_run_name
	task = p_task
	task_runner = p_task_runner
	
	clear()
	on_begin.connect(func():
		state = TaskState.RUNNING
		begin_time = Time.get_unix_time_from_system()
	)
	on_end.connect(func(status: String):
		state = TaskState.FINISHED
		end_status = status
		end_time = Time.get_unix_time_from_system()
	)
	on_log.connect(func(line: LogLine): logs.push_back(line))
	on_message.connect(func(message: LogMessage): messages.push_back(message))
	
func log_message(message_object):
	on_message.emit(TRTaskRun.LogMessage.new(message_object))

func log(line: String): log_log(line)
func log_log(line: String):
	on_log.emit(TRTaskRun.LogLine.new(LogSeverity.LOG, line))

func log_error(line: String):
	on_log.emit(TRTaskRun.LogLine.new(LogSeverity.ERROR, line))
	
func pipe_to(target: TRTaskRun):
	on_log.connect(func(line): target.on_log.emit(line))
	on_message.connect(func(message): target.on_message.emit(message))
	
func await_end():
	if state == TaskState.FINISHED:
		return
	await on_end

func clear():
	logs.clear()
	messages.clear()
	state = TaskState.NOT_STARTED
	end_status = ""
	begin_time = 0
	end_time = 0
	cancel_requested = false
	subtask_runs.clear()
	cleared.emit()

func run_task():
	var was_cancel_requested = cancel_requested
	clear()
	if was_cancel_requested:
		on_begin.emit()
		on_end.emit("Task Canceled")
		return
	
	var task_executor: Callable = get_task_type().executor
	on_begin.emit()
	var res = await task_executor.call(self)
	on_end.emit(res)
	
func cancel_task():
	cancel_run_requested.emit()
	cancel_requested = true
	for run in subtask_runs:
		run.cancel_task()

func create_subtask(task_name: String, pipe_to_parent: bool = true) -> TRTaskRun:
	var task: TRTask = task_runner.get_task(task_name)
	if task == null:
		return null
	var subtask_run = task_runner.create_run(TRUtils.task_run_name(task.task_name, subtask_runs), task)
	if pipe_to_parent:
		subtask_run.pipe_to(self)
	subtask_run.parent_run = self
	subtask_runs.push_back(subtask_run)
	if cancel_requested:
		subtask_run.cancel_task()
	task_runner.on_run_added.emit(subtask_run)
	return subtask_run

func run_subtask(task_name: String, pipe_to_parent: bool = true) -> TRTaskRun:
	var task = create_subtask(task_name, pipe_to_parent)
	task.run_task()
	return task

func create_anon_subtask(run_name: String, task_func: Callable) -> TRTaskRun:
	var subtask_run = task_runner.create_run(run_name, TRTask.new_callable("IN_EDITOR_CALLABLE", "__anonymous_task__", task_func))
	subtask_run.parent_run = self
	subtask_runs.push_back(subtask_run)
	if cancel_requested:
		subtask_run.cancel_task()
	task_runner.on_run_added.emit(subtask_run)
	return subtask_run

func _create_proxy_subtask(run_name: String) -> TRTaskRun:
	var run: TRTaskRun = task_runner.create_run(
		run_name, 
		TRTask.new_callable("PROXY", run_name, func(proxy_run: TRTaskRun): pass)
	)
	run.parent_run = self
	subtask_runs.push_back(run)
	if cancel_requested:
		run.cancel_task()
	task_runner.on_run_added.emit(run)
	return run

func run_anon_subtask(run_name: String, method: Callable) -> TRTaskRun:
	var st: TRTaskRun = create_anon_subtask(run_name, method)
	st.run_task()
	return st

func get_real_parent() -> TRTaskRun:
	var real_run: TRTaskRun = self
	while real_run.get_task_type().hidden:
		real_run = real_run.parent_run
		if real_run == null: return null
	return real_run

func get_root_task() -> TRTaskRun:
	var root_run: TRTaskRun = self
	while root_run.parent_run != null:
		root_run = root_run.parent_run
	return root_run

	
func get_task_type() -> TRTaskRunner.TaskType:
	return task_runner.task_types[task.task_type]

enum LogSeverity {
	LOG,
	ERROR
}

enum TaskState {
	NOT_STARTED,
	RUNNING,
	FINISHED
}

class Log extends RefCounted:
	var timestamp: float

class LogLine extends Log:
	var severity: LogSeverity
	var line: String
	
	func _init(p_severity: LogSeverity, p_line: String):
		timestamp = Time.get_unix_time_from_system()
		line = p_line
		severity = p_severity
		
	func log_string():
		return "[" + TRUtils.format_time(timestamp) + " " + LogSeverity.keys()[severity] + "] " + line
	
class LogMessage extends Log:
	var message: Variant
	
	func _init(p_message: Variant):
		timestamp = Time.get_unix_time_from_system()
		message = p_message
	
	func log_string():
		return "[" + TRUtils.format_time(timestamp) + "] " + JSON.stringify(message)
