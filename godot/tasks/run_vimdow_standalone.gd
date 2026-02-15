func run(r: TRTaskRun):
	r.log("Building Rust Library 🦀")
	var cargo = r.run_subtask("cargo build")
	await cargo.await_end()
	
	r.log(cargo.end_status)
	if cargo.end_status.contains("error"):
		r.log("Failed to build rust library")
		return
	else:
		EditorInterface.play_main_scene()
