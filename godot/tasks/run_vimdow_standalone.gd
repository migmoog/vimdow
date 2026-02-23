func edit_file(r: TRTaskRun, file: String):
	ProjectSettings.set_setting("vimdow/edit_file", file)
	r.log('📁 opening file: "%s"' % ProjectSettings.get_setting("vimdow/edit_file"))
	run(r)
	await r.await_end()
	assert(ProjectSettings.get_setting("vimdow/edit_file") == file)
	ProjectSettings.set_setting("vimdow/edit_file", "")

func run(r: TRTaskRun):
	r.log("Building Rust Library 🦀")
	var cargo = r.run_subtask("cargo build")
	await cargo.await_end()
	
	if cargo.end_status.contains("101"):
		const MSG = "Failed to build rust library"
		r.log(MSG)
		r.on_end.emit(MSG)
		return
	else:
		r.log("Running vimdow standalone ️")
		EditorInterface.play_main_scene()
		r.on_end.emit("")
