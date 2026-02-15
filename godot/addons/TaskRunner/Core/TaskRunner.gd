@tool
class_name TRTaskRunner
extends RefCounted
static var singleton_instance: TRTaskRunner

static func get_singleton() -> TRTaskRunner:
	if not singleton_instance:
		singleton_instance = TRTaskRunner.new()
	return singleton_instance

static func clear_singleton():
	singleton_instance = null

static var TASKS_KEY: String = "task_runner/tasks"
static var DOCS_LINK: String = "https://github.com/Rushdown-Studios/GodotTaskRunner/tree/main/addons/TaskRunner/Docs"

class TaskType:
	var type_name: String
	var type_extensions: Array[String]
	var hidden: bool = false
	var executor: Callable
	var sample_script: String
	func friendly_name():
		return type_name.to_lower().replace("_", " ")
	func _init(c: Dictionary):
		type_name = c.type_name if c.has("type_name") else ""
		type_extensions.assign(c.type_extensions if c.has("type_extensions") else []) # handles Array -> Array[String] assignment correctly
		hidden = c.hidden if c.has("hidden") else false
		executor = c.executor if c.has("executor") else func(r: TRTaskRun): return "done"
		sample_script = c.sample_script if c.has("sample_script") else ""

var tasks: Array[TRTask] = []
var task_runs: Array[TRTaskRun] = []
var task_types: Dictionary[String, TaskType] = {}

signal on_task_added(TRTask) # new task
signal on_task_updated(TRTask) # updated task
signal on_task_removed(TRTask) # deleted task's name
signal on_tasks_reordered()

signal on_run_added(TRTaskRun)
signal on_run_removed(TRTaskRun)
signal on_task_type_added

func _init() -> void:
	load_tasks()

func has_task(task_name: String):
	return get_task(task_name) != null

static func bootstrap_task_file(task_type: String, task_name: String, task_file: String, override: bool = false):
	var new_task: TRTask = TRTask.new_on_disk(task_type, task_name, task_file)
	get_singleton().add_task(new_task, override)

static func bootstrap_inline_task_from_file(task_type: String, task_name: String, task_file: String, override: bool = false):
	bootstrap_task(task_type, task_name, FileAccess.get_file_as_string(task_file), override)

static func bootstrap_task(task_type: String, task_name: String, task_command: String, override: bool = false):
	var new_task: TRTask = TRTask.new_inline(task_type, task_name, task_command)
	get_singleton().add_task(new_task, override)

func add_task(new_task: TRTask, override: bool = false):
	var runner: TRTaskRunner = get_singleton()
	if runner.has_task(new_task.task_name):
		if not override:
			return

		var current_task := runner.get_task(new_task.task_name)
		if not current_task.equals(new_task):
			runner.remove_task(current_task.task_name)

	tasks.push_back(new_task)
	save_tasks()
	on_task_added.emit(new_task)

func update_task(updated_task: TRTask):
	save_tasks()
	on_task_updated.emit(updated_task)

func remove_task(task_name: String):
	var task = get_task(task_name)
	tasks.erase(task)
	save_tasks()
	on_task_removed.emit(task)

func load_tasks():
	tasks.clear()
	if ProjectSettings.has_setting(TASKS_KEY):
		var tasks_array: Array = ProjectSettings.get_setting(TASKS_KEY)
		for task_dict in tasks_array:
			var task: TRTask = TRTask.from_dict(task_dict)
			tasks.push_back(task)
			on_task_added.emit(task.task_name)

func save_tasks():
	var task_arr: Array = []
	for task in tasks:
		task_arr.push_back(task.to_dict())

	ProjectSettings.set_setting(TASKS_KEY, task_arr)
	ProjectSettings.save()

func unique_task_name():
	var idx: int = 1
	var task_names = {}
	for task in tasks:
		task_names[task.task_name] = true
	while true:
		var name = "Task " + str(idx)
		if not task_names.has(name):
			return name
		idx += 1

func get_task(task_name: String) -> TRTask:
	for task in tasks:
		if task.task_name == task_name:
			return task
	return null

func create_run(run_name: String, task: TRTask) -> TRTaskRun:
	return TRTaskRun.new(run_name, task, self)

func add_run(task_name: String, run_name = null) -> TRTaskRun:
	var task: TRTask = get_task(task_name)
	if task == null:
		return null
	if not run_name:
		run_name = TRUtils.task_run_name(task.task_name, task_runs)
	var run = create_run(run_name, task)
	task_runs.push_back(run)
	on_run_added.emit(run)
	return run

func execute_run(task_name: String, run_name = null) -> TRTaskRun:
	var run: TRTaskRun = add_run(task_name, run_name)
	run.run_task()
	return run

func delete_run(task_run: TRTaskRun):
	var to_delete: TRTaskRun = task_run.get_root_task()
	for run_idx in task_runs.size():
		if task_runs[run_idx] == to_delete:
			task_runs.remove_at(run_idx)
			to_delete.cancel_task()
			to_delete.clear()
			on_run_removed.emit(to_delete)
			return

func register_type(p_task_ctor_args: Dictionary):
	var task_type: TaskType = TaskType.new(p_task_ctor_args)
	task_types[task_type.type_name] = task_type

	# Ensure the file extensions we registered can be seen in the editor
	if Engine.is_editor_hint():
		var current_settings: PackedStringArray = EditorInterface.get_editor_settings().get_setting("docks/filesystem/textfile_extensions").split(",")
		for ext in task_type.type_extensions:
			if ext.to_lower() == "gd": continue
			if current_settings.has(ext): continue
			current_settings.push_back(ext)
		EditorInterface.get_editor_settings().set_setting("docks/filesystem/textfile_extensions", ",".join(current_settings))

	on_task_type_added.emit()

func move_task(task_name: String, dist: int):
	var current_task: TRTask = get_task(task_name)
	if not current_task: return

	for idx in tasks.size():
		var task = tasks[idx]
		if task.task_name == task_name:
			if idx + dist < tasks.size() && idx + dist >= 0:
				tasks.remove_at(idx)
				tasks.insert(idx + dist, task)
				save_tasks()
				on_tasks_reordered.emit()
				return

func file_task_type(file_path: String) -> TaskType:
	var parts = file_path.split(".")
	if parts.size() <= 1:
		return null

	var extension = parts[parts.size()-1].to_lower()
	for type in task_types.values():
		if type.type_extensions.has(extension):
			return type

	return null

func file_task_type_with_defaults(file_path: String) -> TaskType:
	var task_type: TaskType = file_task_type(file_path)
	if task_type == null:
		# Assume ps1 on windows, else bash because the file extension didn't tell us. User can change it in the UI if we guessed wrong.
		return file_task_type("dummy.ps1" if OS.get_name() == "Windows" else "dummy.sh")

	return task_type
