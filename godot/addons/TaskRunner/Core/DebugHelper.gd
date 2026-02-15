@tool
extends RefCounted
class_name TRDebugHelper

static var ENABLE_DEBUG_BUTTON_TEXT: String = "Keep Debug Server Open"

var editor_settings: EditorSettings
var r: TRTaskRun

func _init(p_run: TRTaskRun):
	r = p_run
	editor_settings = EditorInterface.get_editor_settings()
	ensure_debugger_started() # implcitly turn on the debugger

func ensure_debugger_started():
	# store if the debugger was already enabled so we can disable it when done, if needed
	var was_debugger_running: bool = false
	
	# The classes you need to ensure the remote debugger is running aren't exposed,
	# so automate clicking the UI that enables the debugger instead
	var base_control = EditorInterface.get_base_control()
	var menu_bar = base_control.find_child("*MenuBar*", true, false)
	var debug_menu: PopupMenu = menu_bar.get_node("Debug")
	for i in debug_menu.get_item_count():
		if debug_menu.get_item_text(i) == tr(ENABLE_DEBUG_BUTTON_TEXT):
			was_debugger_running = debug_menu.is_item_checked(i)
			if not was_debugger_running:
				# Checking the box alone isn't enough, we need to pump the id_pressed signal to
				# force the debugger to actually enable :)
				debug_menu.id_pressed.emit(debug_menu.get_item_id(i))
				r.log("Enabled remote debugger")
			else:
				r.log("Debugger already enabled, won't toggle")
			break

	r.on_end.connect(func(s):
		if was_debugger_running: return
		editor_settings.set_project_metadata("debug_options", "server_keep_open", false)
		for i in debug_menu.get_item_count():
			if debug_menu.get_item_text(i) == tr(ENABLE_DEBUG_BUTTON_TEXT):
				# If needed, disable the remote debugger
				debug_menu.id_pressed.emit(debug_menu.get_item_id(i))
				r.log("Disabled remote debugger")
				break
	, ConnectFlags.CONNECT_ONE_SHOT)

func debug_address():
	var s = EditorInterface.get_editor_settings()
	var host = editor_settings.get_setting("network/debug/remote_host")
	var port = editor_settings.get_setting("network/debug/remote_port")
	return "tcp://" + str(host) + ":" + str(port)

func create_scene_task(scene: String, user_args: Array[String] = []) -> TRTaskRun:
	return r.create_anon_subtask("run " + scene, func(r: TRTaskRun):
		var command: Array[String] = [OS.get_executable_path(), 
			"--project", scene, 
			"--remote-debug", debug_address()]
		if user_args.size() > 0:
			command.append("--")
			command.append_array(user_args)
		return await TRCommonTaskTypes.execute_shell_task(command, r)
	)
	
func run_scene_task(scene: String, user_args: Array[String] = []) -> TRTaskRun:
	var st: TRTaskRun = create_scene_task(scene, user_args)
	st.run_task()
	return st
