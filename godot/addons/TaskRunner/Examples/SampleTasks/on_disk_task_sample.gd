@tool
extends RefCounted
class_name TROnDiskTaskSample

# In this sample, we show that tasks can be saved as files on disk.
func run(r: TRTaskRun):
	# Typically, Task Runner tasks are saved as a variable in the project's project.godot file
	# It is possible to store the task as a file on disk instead.
	
	# When a task is stored on disk, it's path is included in the project.godot file instead of the contents of the task.
	# All types of tasks (powershell, bash, gdscript) can be saved on disk.
	
	r.log("On disk task hello world")
	
