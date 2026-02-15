
# This is a sample GDScript script
# GDScript tasks can be run in the editor process like a tool script, or in a background godot process.
# Use the dropdown below to switch between "new process gdscript" and "in editor gdscript" modes.
func run(r: TRTaskRun):
	
	r.log("Logs will be displayed in the task runner")
	r.log_error("Error logs will also be displayed")
	print("If the task is run in a new process, stdout and stderr logs are also capture")
	print("If it is run in editor, print logs will not be captured and you must use r.log")

	# You can output structured json messages.
	# These messages can be caught and handled in a parent task.
	# Messages can be sent from a new process to the editor process.
	r.log_message({"build_status": "PASSED"})

	# Tasks run in the background. Long sleeps are handled gracefully.
	r.log("Sleeping for 5 seconds")
	await Engine.get_main_loop().create_timer(5).timeout
	r.log("Sleep finished")

	# You may optionally return an exit status string.
	return "15"
