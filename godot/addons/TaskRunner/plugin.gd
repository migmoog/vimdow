@tool
extends EditorPlugin

@export var dock_scene = preload("res://addons/TaskRunner/Dock/TaskRunnerDock.tscn")
var dock: TRTaskRunnerDock

func _enter_tree():
	dock = dock_scene.instantiate()
	dock.runner = TRTaskRunner.get_singleton()
	TRCommonTaskTypes.register(dock.runner)
	
	# set default properties so users can see them in the project editor
	TRUtils.get_project_setting(TRNewTaskDialog.DEFAULT_TASK_FOLDER_KEY, TRNewTaskDialog.DEFAULT_TASK_FOLDER)
	TRUtils.get_project_setting(TRCommonTaskTypes.TASK_MESSAGE_PREFIX, TRCommonTaskTypes.DEFAULT_TASK_MESSAGE_PREFIX)
	TRUtils.get_project_setting(TRCommonTaskTypes.SHELL_EXECUTABLE, TRCommonTaskTypes.DEFAULT_SHELL_EXECUTABLE)
	TRUtils.get_project_setting(TRTaskRunner.TASKS_KEY, [])
	
	add_control_to_bottom_panel(dock, "Task Runner")
	
	scene_saved.connect(func(_scene):
		dock.task_tab.save_current_task()
	)
	
	resource_saved.connect(func(_resource):
		dock.task_tab.save_current_task()
	)
	
func _exit_tree():
	remove_control_from_bottom_panel(dock)
	dock.free()
	TRTaskRunner.clear_singleton()
	
