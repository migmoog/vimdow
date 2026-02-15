@tool
class_name TRCommonTaskTypes
extends RefCounted

static var TASK_MESSAGE_PREFIX: String = "task_runner/shell_execute/message_prefix"
static var DEFAULT_TASK_MESSAGE_PREFIX: String = "TRTASK_MESSAGE_PREFIX"
static var SHELL_EXECUTABLE: String = "task_runner/shell_execute/executable"
static var DEFAULT_SHELL_EXECUTABLE = ["bash"]

static func register(task_runner: TRTaskRunner):
	task_runner.register_type({
		"type_name": "BASH",
		"executor": shell_execute,
		"type_extensions": ["sh"],
		"sample_script": "echo \"hello world\""
	})
	task_runner.register_type({
		"type_name": "POWERSHELL",
		"executor": powershell_execute,
		"type_extensions": ["ps1"],
		"sample_script": "write-output \"hello world\""
	})
	task_runner.register_type({
		"type_name": "CMD",
		"executor": cmd_execute,
		"type_extensions": ["bat", "cmd"],
		"sample_script": "echo \"hello world\""
	})
	task_runner.register_type({
		"type_name": "NEW_PROCESS_GDSCRIPT",
		"executor": gdscript_execute,
		"type_extensions": ["gd"],
		"sample_script": """func run(r: TRTaskRun):
	r.log("hello world")
	
	return "done"
		"""
	})
	task_runner.register_type({
		"type_name": "IN_EDITOR_GDSCRIPT",
		"executor": editor_gdscript_register,
		"type_extensions": ["gd"],
		"sample_script": """func run(r: TRTaskRun):
	r.log("hello world")
	
	return "done"
		"""
	})
	task_runner.register_type({
		"type_name": "IN_EDITOR_CALLABLE",
		"executor": callable_register,
		"hidden": true
	})
	task_runner.register_type({
		"type_name": "PROXY",
		"executor": func(r): pass, # this should never be called
		"hidden": true
	})

static func shell_execute(r: TRTaskRun):
	var file: FileAccess = to_temp_file(r)
	return await execute_shell_task(
		TRUtils.get_project_setting(SHELL_EXECUTABLE, DEFAULT_SHELL_EXECUTABLE) + [file.get_path_absolute()],
		r
	)

static func powershell_execute(r: TRTaskRun):
	var file: FileAccess = to_temp_file(r)
	return await execute_shell_task(
		["powershell.exe", "-File", file.get_path_absolute()],
		r
	)

static func cmd_execute(r: TRTaskRun):
	var fa: FileAccess = to_temp_file(r)
	return await execute_shell_task(
		["cmd.exe", "/c", fa.get_path_absolute()],
		r
	)

static func callable_register(r: TRTaskRun):
	if r.task.task_source != TRTask.TaskSource.CALLABLE:
		print("IN_EDITOR_CALLABLE only supports callable task source")
		return "done"
	
	var res = await r.task.get_task_callable().call(r)
	return str(res) if res else "done"

static func editor_gdscript_register(r: TRTaskRun):
	var script_obj: Object
	match r.task.task_source:
		TRTask.TaskSource.INLINE:
			var script: GDScript = GDScript.new()
			script.source_code = "@tool\n" + r.task.get_task_command()
			script.reload()
			script_obj = RefCounted.new()
			script_obj.set_script(script)
		TRTask.TaskSource.ON_DISK:
			script_obj = load(r.task.get_task_filepath()).new()
		_:
			print("editor_gdscript_register must be called with ether an ON_DISK or INLINE task definition")
			return "done"
		
	if script_obj.has_method("run"):
		var res = await script_obj.call("run", r)
		return str(res) if res else "done"
	else:
		print("task must have method 'run' which takes the TRTaskRun as an argument")
		return "done"

static func gdscript_execute(root_run: TRTaskRun):
	# We are spawning a child editor process which may itself spawn many child processes
	# In this editor, we will have a fake TRTaskRun for each task that acts as a proxy for the real task in the child process
	var proxy_runs: Dictionary[String, TRTaskRun] = {}
	proxy_runs[root_run.run_name] = root_run # Add the root task to the set of proxy tasks, as it is also a dummy local task corosponding to the child processes task
	var root_exit_status: Dictionary = {} # This is just meant to hold a string, but strings are pass by value and we need it to be pass by reference
	
	# This is a hidden task that will not appear in the Task Runs panel.
	# It exists to be passed into execute_shell_task and receive messages from the child process and raise events on the correct proxies
	var subprocess_bridge: TRTaskRun = TRTaskRunner.get_singleton().create_run(
		root_run.run_name + " Subprocess Bridge Run",
		TRTask.new_callable("PROXY", root_run.task.task_name + " Subprocess Bridge Task", func(r: TRTaskRun): pass)) # this method will never be run
		
	subprocess_bridge.on_message.connect(func(m: TRTaskRun.LogMessage):
		# We are receiving messages from the child editor process. See TRTaskRunnerCLI.emit_message for the format
		if not m.message.has("run_name") or not m.message.has("type") or not m.message.has("payload"):
			print("Received malformed control message: " + str(m.message))
			return
		var run_name = m.message.run_name
		var run_type = m.message.type
		var payload = m.message.payload
		# Leaving these here because it's very common to use them to debug what messages we received from the child process and what proxies we have
		# print("CM | " + str(run_type) + " " + run_name + " - " + str(payload))
		# print("proxies | " + str(proxy_runs.keys()))
		var proxy_run = proxy_runs[run_name] if proxy_runs.has(run_name) else null
		match run_type:
			"control_message_end":
				# Indicates a task run in the child process has ended.
				if not proxy_run: return
				if run_name == root_run.run_name:
					# The root run is special. We store it's exit status, but don't actually emit the on_end event. Instead,
					# it will be emitted once the child process exits
					root_exit_status["status"] = payload.end_status
				else:
					# End the proxy run. The run wasn't actually started, so there isn't an executor to do this, so we do it manually.
					proxy_run.on_end.emit(payload.end_status)
			"control_message_message":
				# A child task has emitted a message.
				if not proxy_run: return
				proxy_run.log_message(payload)
			"control_message_log":
				# Logs from a child task.
				if not proxy_run: return
				match TRTaskRun.LogSeverity.get(payload.severity):
					TRTaskRun.LogSeverity.LOG: proxy_run.log(payload.message)
					TRTaskRun.LogSeverity.ERROR: proxy_run.log_error(payload.message)
			"control_message_task_created":
				# A new task has been created in the child process. We must create a proxy to track it.
				if not proxy_runs.has(payload.run_parent_name):
					# : Support starting multiple non-child tasks in a seperate editor process. Not really useful, but it's an uglyness in the API
					print("Creating proxy run which is not a child of any existing runs.")
					return
				
				# Create the proxy and pretend like it started without calling it's no-op executor
				proxy_runs[run_name] = proxy_runs[payload.run_parent_name]._create_proxy_subtask(run_name)
				proxy_runs[run_name].clear()
				proxy_runs[run_name].on_begin.emit()
	)
	
	# Spawn the background editor process.
	await execute_shell_task(
		[OS.get_executable_path(), 
			"--headless", "--no-header",
			"--script", "res://addons/TaskRunner/TaskRunnerCLI.gd",
			"--",
			"--run-task", root_run.task.task_name,	# Task name tells the child process which task to run
			"--run-name", root_run.run_name, 		# Task run name needs to match what we think it's named in the parent process
			"--emit-messages", "true",				# Tells the child process to format the output as json instead of as human readable strings
		],
		subprocess_bridge
	)
	
	# Check if the root task had an exit status.
	if not root_exit_status.has("status"): root_exit_status.status = "done"
	return root_exit_status.status

static func execute_shell_task(shell_executable: Array, r: TRTaskRun):
	var task_message_prefix = TRUtils.get_project_setting(TASK_MESSAGE_PREFIX, DEFAULT_TASK_MESSAGE_PREFIX)
	
	var read_line = func(file: FileAccess, severity: TRTaskRun.LogSeverity):
		while file.is_open() and (file.get_position() < file.get_length()):
			var line = file.get_line()
			if line.length() > 0:
				# To send structured data from a child process to the task runner, log a json object prefixed with the DEFAULT_TASK_MESSAGE_PREFIX
				var was_message: bool = false
				var trimmed = line.strip_edges(true, true)
				if trimmed.begins_with(task_message_prefix):
					var message_str = trimmed.trim_prefix(task_message_prefix)
					var message_var = JSON.parse_string(message_str)
					if message_var != null:
						was_message = true
						r.log_message(message_var)
				if not was_message:
					match severity:
						TRTaskRun.LogSeverity.LOG: r.log_log(line)
						TRTaskRun.LogSeverity.ERROR: r.log_error(line)
	
	var exec_props = OS.execute_with_pipe(shell_executable[0], shell_executable.slice(1))

	var stdio: FileAccess = exec_props.stdio
	var stderr: FileAccess = exec_props.stderr

	var kill_called = false
	while OS.is_process_running(exec_props.pid):
		if r.cancel_requested and not kill_called:
			OS.kill(exec_props.pid)
			kill_called = true # don't spam this over and over, let the process exit if possible
		read_line.call(stdio, TRTaskRun.LogSeverity.LOG)
		read_line.call(stderr, TRTaskRun.LogSeverity.ERROR)
		await Engine.get_main_loop().process_frame # create_timer(1).timeout

	# Read any remaining output
	read_line.call(stdio, TRTaskRun.LogSeverity.LOG)
	read_line.call(stderr, TRTaskRun.LogSeverity.ERROR)
	
	return str(OS.get_process_exit_code(exec_props.pid))

static func to_temp_file(r: TRTaskRun) -> FileAccess:
	# if the file is already on disk, just return it's path. Otherwise, write a temp file
	var file: FileAccess
	if r.task.task_source == TRTask.TaskSource.ON_DISK:
		file = FileAccess.open(r.task.get_task_filepath(), FileAccess.READ_WRITE)
	else:
		# create_temp cleans up the file automatically
		file = FileAccess.create_temp(FileAccess.READ_WRITE, "tr_temp_task", "." + r.get_task_type().type_extensions[0])
		file.store_string(r.task.get_task_command())

	# mark executable on unixes. Unsure why builting set execute bit function doesn't work, so shelling out to chmod
	match OS.get_name():
		"macOS", "Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD", "Android":
			OS.execute("chmod", ["+x", file.get_path_absolute()])
			
	file.close() # command will need to read from the file, but we need to keep the FileAccess in scope so the temp file isn't discarded. So close it but force callers to keep it in scope.
	return file
