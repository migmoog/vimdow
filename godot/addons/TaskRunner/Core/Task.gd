@tool
class_name TRTask
extends RefCounted

enum TaskSource {
	INLINE,
	ON_DISK,
	CALLABLE
}

var task_type: String
var task_name: String
var task_source: TaskSource

var _task_command: String
var _task_filepath: String
var _task_callable: Callable

static func new_inline(p_task_type: String, p_task_name: String, p_task_command: String) -> TRTask:
	var task = TRTask.new()
	task.task_name = p_task_name
	task.task_type = p_task_type
	task.task_source = TaskSource.INLINE
	task._task_command = p_task_command
	task._task_filepath = ""
	task._task_callable = func(): pass
	return task

static func new_on_disk(p_task_type: String, p_task_name: String, p_task_filepath: String) -> TRTask:
	var task = TRTask.new()
	task.task_name = p_task_name
	task.task_type = p_task_type
	task.task_source = TaskSource.ON_DISK
	task._task_command = ""
	task._task_filepath = p_task_filepath
	task._task_callable = func(): pass
	return task
	
static func new_callable(p_task_type: String, p_task_name: String, p_task_callable: Callable) -> TRTask:
	var task = TRTask.new()
	task.task_name = p_task_name
	task.task_type = p_task_type
	task.task_source = TaskSource.CALLABLE
	task._task_command = ""
	task._task_filepath = ""
	task._task_callable = p_task_callable
	return task

func to_dict() -> Dictionary:
	return {
		"task_type": task_type,
		"task_name": task_name,
		"task_source": TaskSource.keys()[task_source],
		"task_command": _task_command,
		"task_filepath": _task_filepath,
	}

static func from_dict(task_dict: Dictionary) -> TRTask:
	if not task_dict.has("task_source"):
		push_warning("Task does not have task_source, assuming INLINE")
		task_dict["task_source"] = TaskSource.keys()[TaskSource.INLINE]
	
	if not task_dict.has("task_filepath"):
		push_warning("Task does not have task_filepath, assuming empty string")
		task_dict["task_filepath"] = ""
	
	if not task_dict.has("task_command"):
		push_warning("Task does not have task_command, assuming empty string")
		task_dict["task_command"] = ""
	
	var task = TRTask.new()
	task.task_name = task_dict["task_name"]
	task.task_type = task_dict["task_type"]
	task.task_source = TaskSource.get(task_dict["task_source"])
	task._task_command = task_dict["task_command"]
	task._task_filepath = task_dict["task_filepath"]
	task._task_callable = func(): pass # can't serialize a callable
	return task
	

func update_props(other_task: TRTask):
	task_name = other_task.task_name
	task_type = other_task.task_type
	task_source = other_task.task_source
	_task_command = other_task._task_command
	_task_filepath = other_task._task_filepath
	_task_callable = other_task._task_callable

func copy():
	var task = TRTask.new()
	task.task_name = self.task_name
	task.task_type = self.task_type
	task.task_source = self.task_source
	task._task_command = self._task_command
	task._task_filepath = self._task_filepath
	task._task_callable = self._task_callable
	return task

func equals(other_task: TRTask):
	return task_name == other_task.task_name and \
		task_type == other_task.task_type and \
		task_source == other_task.task_source and \
		_task_command == other_task._task_command and \
		_task_filepath == other_task._task_filepath

func set_task_command(p_task_command: String):
	_task_command = p_task_command
	
func get_task_command() -> String:
	return _task_command

func get_task_callable() -> Callable:
	return _task_callable

func get_task_filepath() -> String:
	if task_source == TaskSource.INLINE:
		return "[INLINE]"
	return _task_filepath

func set_task_filepath(p_task_filepath: String):
	_task_filepath = p_task_filepath
