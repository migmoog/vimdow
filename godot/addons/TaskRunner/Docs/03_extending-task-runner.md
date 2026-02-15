# Extending The Task Runner

The Task Runner is designed to be extensible. You can add support for new scripting languages, register tasks programmatically, and integrate the Task Runner into your own plugins.
This document covers how to work with the Task Runner and extend it's functionality.

## Table of Contents

- [Programmatic Task Registration](#programmatic-task-registration)
    - [Creating Tasks](#creating-tasks)
    - [Example: Plugin-Provided Tasks](#example-plugin-provided-tasks)
    - [Example: Conditional Registration](#example-conditional-registration)
    - [Example: Dynamic Task Generation](#example-dynamic-task-generation)
- [Adding New Task Types](#adding-new-task-types)
    - [Registration API](#registration-api)
    - [Task Type Config Dictionary](#task-type-config-dictionary)
    - [Example: Adding a Python Task Type](#example-adding-a-python-task-type)
    - [Reference Implementation](#reference-implementation)
- [Best Practices](#best-practices)

## Programmatic Task Registration

It is possible to add tasks to the Task Runner programmatically. This can be useful if you're writing
a separate plugin and want to add tasks from your plugin to the Task Runner.
It can also be useful for dynamically generating tasks or when building a library of tasks for your team.

When you add a task to the Task Runner it is written into the project.godot file, so be mindful that tasks will persist across editor restarts.

See [BootstrapTasks.gd](../Examples/BootstrapTasks.gd) for an example of checking for the Task Runner plugin and safely adding tasks.

### Creating Tasks

There's a few ways to add tasks to the Task Runner, but the simplest one is to use the bootstrap methods in `TRTaskRunner`.

*`static func bootstrap_task_file(task_type: String, task_name: String, task_file: String, override: bool = false)`*

* `task_type` (String): The new tasks's type, eg, "BASH", "IN_EDITOR_GDSCRIPT".
* `task_name` (String): A name for the new task.
* `task_file` (String): The on disk file the task represents. Eg `res://tasks/my_task.gd`.
* `override` (bool): If a task of this name already exists, should it be overridden? True will override, false will not.

*`static func bootstrap_inline_task_from_file(task_type: String, task_name: String, task_file: String, override: bool = false)`*
* `task_type` (String): The new tasks's type, eg, "BASH", "IN_EDITOR_GDSCRIPT".
* `task_name` (String): A name for the new task.
* `task_file` (String): The on disk file which will be read into memory and used as the content of the task.
* `override` (bool): If a task of this name already exists, should it be overridden? True will override, false will not.
	

*`static func bootstrap_task(task_type: String, task_name: String, task_command: String, override: bool = false)`*
* `task_type` (String): The new tasks's type, eg, "BASH", "IN_EDITOR_GDSCRIPT".
* `task_name` (String): A name for the new task.
* `task_command` (String): The string content of the task. Eg `echo 'hello world'` for a bash task.
* `override` (bool): If a task of this name already exists, should it be overridden? True will override, false will not.

The difference between `bootstrap_task_file` and `bootstrap_inline_task_from_file` is subtle. `bootstrap_task_file` makes a task which points to the file on disk.
`bootstrap_inline_task_from_file` will copy the content of the file on disk into memory and save it as part of the task in your project.godot file. Use whichever is appropriate to your situation.

Example:
	
```gdscript
TRTaskRunner.bootstrap_task_file("IN_EDITOR_GDSCRIPT", "New GDScript Task", "res://tasks/my_task.gd")
TRTaskRunner.bootstrap_inline_task_from_file("IN_EDITOR_GDSCRIPT", "New GDScript Task", "res://tasks/my_task.gd") # Will not overwrite existing "New GDScript Task" task
TRTaskRunner.bootstrap_task("BASH", "New Bash Task", "echo 'hello world'", true) # will overwrite existing "New Bash Task" task
```

### Example: Plugin-Provided Tasks

Register tasks when your plugin is enabled:

```gdscript
# my_plugin.gd
extends EditorPlugin

func _enter_tree():

	# Check if the TaskRunner plugin exists
	if EditorInterface.is_plugin_enabled("TaskRunner"):
		# If it does, get a handle on the TaskRunner itself.
		# Use load to avoid referencing TRTaskRunner, which will not be defined if the TaskRunner plugin does not exist.
		var TaskRunner = load("res://addons/TaskRunner/Core/TaskRunner.gd")
	
		# Register a build task
		TaskRunner.bootstrap_task_file(
			"BASH",
			"Build Plugin Assets",
			"res://addons/my_plugin/scripts/build_assets.sh"
		)
		
		# Register a test task
		TaskRunner.bootstrap_task(
			"IN_EDITOR_GDSCRIPT",
			"Run Plugin Tests",
			"""
func run(r):
	r.log("Running plugin tests...")
	# Test logic here
	r.log("All tests passed!")
			"""
	)
```

### Example: Conditional Registration

Register tasks based on project configuration:

```gdscript
func _ready():
	await get_tree().process_frame

	# Only register export tasks if export presets exist
	if FileAccess.file_exists("res://export_presets.cfg"):
		_register_export_tasks()

	# Only register deployment tasks if configured
	if ProjectSettings.has_setting("deployment/enabled"):
		_register_deployment_tasks()

	# Register development tasks only in debug mode
	if OS.is_debug_build():
		_register_dev_tasks()

	func _register_export_tasks():
		TRTaskRunner.bootstrap_task(
			"IN_EDITOR_GDSCRIPT",
			"Export All Platforms",
			"""
func run(r):
	var platforms = ['Windows', 'Linux', 'Mac']
	for platform in platforms:
	r.log('Exporting ' + platform + '...')
	var export_task = r.spawn_task('Export ' + platform)
	await export_task.finished
	r.log('All exports complete!')
			"""
		)
```

### Example: Dynamic Task Generation

Generate tasks from configuration data:

```gdscript
func _ready():
	await get_tree().process_frame
	
	# Load build configuration
	var config_json = JSON.parse_string(FileAccess.get_file_as_string("res://build_config.json"))
	
	# Create a task for each configured build target
	for target in config_json.targets:
		TRTaskRunner.bootstrap_task_file(
			"BASH",
			"Build " + target.name,
			target.script_path
		)
```

## Adding New Task Types

Out of the box, the task runner supports 5 task types - cmd, powershell, bash, in editor gdscript, and new process gdscript.
It is possible to register new task types. The most common reason to add new task types is to support other scripting languages.

The Task Runner has good support for using [`OS.execute_with_pipe`](https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-execute-with-pipe) to spawn background processes.
If you're looking to add support for a new language to the Task Runner, you can likely build off of the existing process running logic without much difficulty.

Note: New Task Types can be used for things other than adding support for new scripting languages. For example, you could add a "send email" task type that sends the body
of the task as an email. The use cases for task types like this are somewhat fuzzy, though, so the documentation will focus on the more obvious use case of supporting new scripting languages.

Note: There are actually two other builtin task types proxy tasks and anonymous tasks, but these are hidden and only used internally.

### Registration API

To add a new task type, call:

```gdscript
TRTaskRunner.get_singleton().register_type(config: Dictionary)
```

Note that task types are not persisted to disk. You must register them every time the editor starts up, likely in a tool script.

### Task Type Config Dictionary

The configuration dictionary has these keys:

- **`type_name` (String):** Unique identifier for this task type
  - Used internally and shown in the UI
  - Typically UPPERCASE_WITH_UNDERSCORES (e.g., "PYTHON", "RUBY", "NODE_JS")
  - This field is persisted to disk when a task is saved. If you re-name your task type, you will have to manually clean up your project.godot file.

- **`executor` (Callable):** Function that executes the task
  - Signature: `func(task_run: TRTaskRun) -> String`
  - Should return a string exit code. This function will be awaited and will typically be async.
  - It is this callable's job to operate the task run. Some aspects of the task run are managed by the Task Runner, but others must be operated by the executor:
	- a begin time - Set by the Task Runner
	- an end time - Set by the Task Runner
	- an exit status - This is the value returned by the executor.
	- a cancellation signal and boolean - Respected by the executor. It is the executor's job to check if this signal has been raised or this flag has been set, and exit early if it has.
	- logs, messages, and error logs - If the task tries to log something, the executor must propagate it to the TRTaskRun it's managing.
	- A state - Set by the Task Runner
  - If you use the `TRCommonTaskTypes.execute_shell_task`, this will all be done for you.

- **`type_extensions` (Array[String]):** The file extensions associated with this task type
  - Used when importing tasks or creating new tasks.
  - Examples: `["py"]`, `["js", "mjs"]`, `["rb"]`

- **`sample_script` (String):** Example of what a typical task of this type would look like
  - Used to populate new tasks of this type when they're created from the Add Task dialog.
  - Should be a relatively short example of how to write a task of this type. The user will likely delete it,
	but it may serve as a helpful example.

- **`hidden` (bool):** If the task types should be visible in the Task Runner's GUI.
  - Users should almost always leave this flag set to false. Hidden tasks do not appear in the UI and are generally only used internally.
  - As an example, asynchronous tasks are hidden tasks, as they can only be created via code and cannot be persisted to disk.

### Example: Adding a Python Task Type

```gdscript
# In your plugin.gd file:
func _enter_tree():
	TRTaskRunner.get_singleton().register_type({
		"type_name": "PYTHON",
		"executor": _execute_python,
		"type_extensions": ["py"],
		"sample_script": "print('Hello from Python!')"
	})

func _execute_python(r: TRTaskRun) -> String:
	var file: FileAccess = TRCommonTaskTypes.to_temp_file(r)
	return await TRCommonTaskTypes.execute_shell_task(
		["python3", file.get_path_absolute()],
		r
	)
```

The `TRCommonTaskTypes.to_temp_file()` helper function creates a temporary file with the task's script content and returns a FileAccess object. The file is automatically cleaned up when it goes out of scope after task completion.
The `to_temp_file()` function handles both inline and on-disk tasks gracefully. For inline tasks, it will create a temporary file. For on-disk tasks, it will return a handle to the file on disk.

The `TRCommonTaskTypes.execute_shell_task()` helper function handles subprocess execution using the provided command array and pipes output to the task run.

### Reference Implementation

The included task types are all defined in [addons/TaskRunner/Core/CommonTaskTypes.gd](../Core/CommonTaskTypes.gd). It can be used as a reference when defining new task types. CommonTaskTypes includes the definitions of Bash, PowerShell, Batch, and GDScript task types.

## Best Practices

### Wait for Task Runner to initialize
Wait for Task Runner to initialize before registering tasks:

```gdscript
func _ready():
	await get_tree().process_frame
	register_my_tasks()
```

### Namespace your custom task types and task names
This will keep you organized and help prevent name collisions with other plugins.

```gdscript
"MP_TOOLKIT_PYTHON" # Good
"PYTHON"            # Less Good

"MultiplayerToolkit - Deploy Server" # Good
"Deploy Server"                      # Less Good
```

### Prefer On Disk Tasks for larger tasks
Inline tasks are stored in your `project.godot` file. This is fine for smaller tasks and makes organization easier,
but it can cause more churn on your project.godot file, and you won't be able to edit your tasks in an external editor.

The disadvantage of on disk tasks is if they're moved or renamed, the Task Runner will lose track of them and you'll have to re-associate them.

### Break up your tasks
If you have a task called "generate assets, build, deploy", break it into three separate steps!
There's generally two ways to do this.

*Put each step into a separate script on disk and use load:*
```gdscript
func run(r: TRTaskRun):
	var build = load("res://build_tools/build.gd")
	var deploy = load("res://build_tools/deploy.gd")
	var success = await build.run_build()
	if success == "success":
		await deploy.do_deploy()
```

*Use seperate tasks:*
```gdscript
func run(r: TRTaskRun):
	var success = await r.run_subtask("My Project - Build").await_end()
	if success == "success":
		await r.run_subtask("My Project - Deploy").await_end()
```

Using separate tasks has the advantage of playing nice with the task run visualizer, as each subtask gets its own row.

### Use Messages to communicate
It's often helpful for a parent task to be able to monitor the progress of a subtask.
Instead of scanning the logs of the subtask, you can have the subtask emit a message which the parent
task can receive as a signal.

```gdscript
func run(r: TRTaskRun):
	r.log_message({"status": "success"})
```

### Pay attention to your dependencies
It's common for build tools to have outside dependencies. Be sure to confirm your dependencies actually exist before relying on them.

```gdscript
	func do_build(r: TRTaskRun):
		if not _is_build_tool_available():
			r.log_error("Build tool not found. Please install Build tool via ...")
			return "no_build_tool"
```

### Be careful when programmatically adding tasks and task types
This document outlines how to programmatically register new tasks and task types. There aren't strong best practices around this yet,
so just be careful and try not to step on other developer's toes.

### Be consistent about your return codes
Tasks return an exit status when complete. These exit statuses are strings. When running a bash task, the return code will be the
exit code of the process, but gdscript tasks can return anything. Try to be consistent about your return codes.
