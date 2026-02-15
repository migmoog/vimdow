
# In this sample, we create a yes/no popup in the godot editor and use it's result within the task.
func run(r: TRTaskRun):
	
	# Helper function for creating a confirmation model. Returns true if the user agreed with the prompt.
	var result = await TRUtils.confirm_dialog("Sample Dialog", "Sample Dialog. Are you cool?", "Yeah!", "Not today")
	
	r.log("User confirmed: " + str(result))
	
