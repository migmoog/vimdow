

# In this sample, we spawn a demonstrate how to propogate a messaghe from the child task to the parent.
func run(r: TRTaskRun):
	
	# Create a child task and start it
	var subtask: TRTaskRun = r.run_subtask("Sample - GDScript")
	
	subtask.on_message.connect(func(m: TRTaskRun.LogMessage):
		r.log("Subtask message received: " + m.message.build_status)
	)
	
	# Wait for the child task to end
	await subtask.await_end()
	
	return "Finished"
