func edit_file(r: TRTaskRun, file: String):
	ProjectSettings.set_setting("vimdow/edit_file", file)
	run(r)
	await r.await_end()
	ProjectSettings.set_setting("vimdow/edit_file", "")

func run(r: TRTaskRun):
	r.log("Building Rust Library 🦀")
	var cargo = r.run_subtask("cargo build")
	await cargo.await_end()
	
	if cargo.end_status.contains("101"):
		r.log("Failed to build rust library")
		return
	else:
		EditorInterface.play_main_scene()
