# In this sample, we show some more complicated uses of subtasks.
func run(r: TRTaskRun):
	# In GDScript, a task run is defined as a TRTaskRun. This class has helper methods for spawning child tasks.
	# A task run can be not started, running, or finished.
	
	# You can either create a task run from a named task, or anonymously:
	var named_task: TRTaskRun = r.create_subtask("Sample - GDScript")
	var anon_task: TRTaskRun = r.create_anon_subtask("Anonymous Task", func(subtask_run: TRTaskRun):
		subtask_run.log("hello world")
	)
	
	# These tasks have not started yet. To start them, call:
	named_task.run_task()
	await named_task.await_end() # Then wait for them to finish
	anon_task.run_task()
	await anon_task.await_end()
	
	# Additionally, you can create and run a task via a single method call:
	await r.run_anon_subtask("Anonymous Task 2", func(s): s.log("hello world 2")).await_end()
	
	# By default, all logs from a subtask appear in the parent task's logs. To prevent this, you can set the second argument to false:
	await r.run_subtask("Sample - GDScript", false).await_end()
	
	# Tasks can be canceled. This typically means the background process will be killed, which happens fairly quickly.
	# In the case of in editor gdscript, canceling will set a flag which the task must respect.
	
	# This task typically sleeps for 5 seconds. We will start the task, sleep for 2.5 seconds, then kill the task.
	var background_script: TRTaskRun = r.run_subtask("Sample - GDScript")
	await Engine.get_main_loop().create_timer(2.5).timeout
	background_script.cancel_task()
	
