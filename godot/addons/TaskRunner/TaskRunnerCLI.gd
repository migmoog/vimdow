@tool
extends SceneTree
class_name TRTaskRunnerCLI


var task_name: String
var run_name: String
var run_emit_messages: bool
var force_run_in_editor: bool


# CLI version of the TRTaskRunnerDock, meant to be called like this:
# godot --headless --script --no-header res://addons/TaskRunner/TaskRunnerCLI.gd -- --run-task="Sample - Message Passing"
func _initialize() -> void:
	TRCommonTaskTypes.register(TRTaskRunner.get_singleton())
	
	var cli_args = TRCliArgs.new()
	task_name = cli_args.get_arg(["-rt", "--run-task"], "")
	run_name = cli_args.get_arg(["-rn", "--run-name"], "")
	run_emit_messages = cli_args.get_bool(["-m", "--emit-messages"], false)
	force_run_in_editor = cli_args.get_bool(["--force-run-in-editor"], true)
	
	var task: TRTask = TRTaskRunner.get_singleton().get_task(task_name)
	if force_run_in_editor:
		task.task_type = "IN_EDITOR_GDSCRIPT"
	
	if task == null:
		print("Task not found. Task name: " + task_name)
		exit(1)
	
	var root_run: TRTaskRun = TRTaskRunner.get_singleton().add_run(task_name, run_name if run_name != "" else null)
	if run_name == "": run_name = root_run.run_name
	
	# Root task run and all other task runs should emit all output as messages to be consumed by the parent process
	connect_proxy_emitters(root_run)
	TRTaskRunner.get_singleton().on_run_added.connect(func(new_run: TRTaskRun):
		emit_message("control_message_task_created", new_run.run_name, {
			"run_parent_name": new_run.parent_run.run_name if new_run.parent_run else ""
		})
		connect_proxy_emitters(new_run)
	)
	
	await root_run.run_task()
	exit(0)

func connect_proxy_emitters(r: TRTaskRun):
	r.on_begin.connect(func():
		emit_message("control_message_begin", r.run_name, {
			"start_time": r.begin_time
		})
	)

	r.on_end.connect(func(status: String):
		emit_message("control_message_end", r.run_name, {
			"end_status": status,
			"end_time": r.end_time
		})
	)
	
	r.on_log.connect(func(log: TRTaskRun.LogLine):
		emit_message("control_message_log", r.run_name, {
			"severity": TRTaskRun.LogSeverity.keys()[log.severity],
			"message": log.line
		})
	)
	
	r.on_message.connect(func(message: TRTaskRun.LogMessage):
		emit_message("control_message_message", r.run_name, message.message)
	)

var max_run_name_length: int = 0
func emit_message(type: String, run_name: String, payload):
	if run_name.length() > max_run_name_length: max_run_name_length = run_name.length()
	# log output as messages (so parent editor can parse it) or as strings for human readers
	if run_emit_messages:
		var task_message_prefix = TRUtils.get_project_setting(TRCommonTaskTypes.TASK_MESSAGE_PREFIX, TRCommonTaskTypes.DEFAULT_TASK_MESSAGE_PREFIX)
		print(task_message_prefix + " " + JSON.stringify({
			"type": type,
			"run_name": run_name,
			"payload": payload
		}))
	
	else:
		
		var log_prefix = "[" + TRUtils.format_time(Time.get_unix_time_from_system()) + "][" + run_name.rpad(max_run_name_length) + "] "
		match type:
			"control_message_begin":
				print(log_prefix + "Run started at: " + TRUtils.format_time(payload.start_time))
			"control_message_end":
				print(log_prefix + "Run ended at: " + TRUtils.format_time(payload.end_time) + ". Status: " + payload.end_status)
			"control_message_log":
				match TRTaskRun.LogSeverity.get(payload.severity):
					TRTaskRun.LogSeverity.LOG: print(log_prefix + "LOG " +  payload.message)
					TRTaskRun.LogSeverity.ERROR: printerr(log_prefix + "ERR " + payload.message)
			"control_message_message":
				print(log_prefix + "MSG " + str(payload))
			"control_message_task_created":
				print(log_prefix + "Run created. Parent task run: " + payload.run_parent_name)
				
func exit(code: int):
	TRTaskRunner.clear_singleton()
	quit(code)
