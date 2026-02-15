

# In this sample, we run two scenes in background tasks and connect the debugger to them.
func run(r: TRTaskRun):
	var dh: TRDebugHelper = TRDebugHelper.new(r)
	
	# Start two scenes as background processes and connect the debugger to them
	# Each scene can receive seperate CLI arguments
	# The TRCliArgs class is included in this addon and can optionally be used to parse CLI arguments, if that's useful.
	var scene_one = dh.run_scene_task("res://addons/TaskRunner/Examples/SampleScenes/sample_scene_1.tscn", ["--userdefinedargument", "one"])
	var scene_two = dh.run_scene_task("res://addons/TaskRunner/Examples/SampleScenes/sample_scene_2.tscn", ["--userdefinedargument", "two"])
	
	# Wait for both scenes to exit
	await scene_one.await_end()
	await scene_two.await_end()
