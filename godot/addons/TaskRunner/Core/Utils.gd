class_name TRUtils
extends RefCounted

static func format_time(unix_time: float):
	var datetime = Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d:%02d" % [
		datetime.year,
		datetime.month,
		datetime.day,
		datetime.hour,
		datetime.minute,
		datetime.second
	]

static func get_project_setting(setting_key: String, setting_default_value: Variant):
	if not ProjectSettings.has_setting(setting_key):
		ProjectSettings.set_setting(setting_key, setting_default_value)
		ProjectSettings.set_initial_value(setting_key, setting_default_value)
		ProjectSettings.save()
	return ProjectSettings.get_setting(setting_key)

static func set_project_setting(setting_key: String, setting_value: Variant):
	ProjectSettings.set_setting(setting_key, setting_value)
	if not ProjectSettings.has_setting(setting_key):
		ProjectSettings.set_initial_value(setting_key, setting_value)
	ProjectSettings.save()
	
static func task_run_name(prefix: String, other_runs: Array[TRTaskRun]):
	var taken_names = {}
	for run in other_runs:
		taken_names[run.run_name] = true
	
	var idx = 0
	while true:
		idx += 1
		var next_name = prefix + " " + str(idx)
		if not taken_names.has(next_name):
			return next_name

static func simple_popup_menu(options):
	var menu: PopupMenu = PopupMenu.new()
	menu.popup_hide.connect(func(): menu.queue_free())
	Engine.get_main_loop().root.add_child(menu)
	menu.position = DisplayServer.mouse_get_position()
	var ids = {}
	var option_id = 0
	for option_name in options:
		ids[option_id] = option_name
		menu.add_item(option_name, option_id)
		option_id += 1
	menu.popup()
	
	menu.id_pressed.connect(func(id):
		options[ids[id]].call()
	)


static var _file_task_dialog_open: bool = false
static func create_file_task_dialog(parent_node: Node, access_mode: FileDialog.FileMode, path: String = "") -> FileDialog:
	if _file_task_dialog_open: return null
	_file_task_dialog_open = true

	var file_dialog = FileDialog.new()

	file_dialog.file_mode = access_mode
	file_dialog.access = FileDialog.ACCESS_RESOURCES
	file_dialog.use_native_dialog = false  # Set to true to use OS native dialog
	file_dialog.popup_window = true
	if not path.is_empty():
		file_dialog.current_path = path
	
	for task_type in TRTaskRunner.get_singleton().task_types.values():
		if task_type.hidden: continue
		file_dialog.add_filter(
			", ".join(task_type.type_extensions.map(func(e): return "*." + e)),
			task_type.friendly_name())
		
	file_dialog.confirmed.connect(func(): _file_task_dialog_open = false)
	file_dialog.canceled.connect(func(): _file_task_dialog_open = false)

	# NOTE: file_dialog.confirmed does not appear to be called consistently on FileDialogs
	# To make sure the _file_task_dialog_open is properly reset, explicitly set it to false when a file is selected
	file_dialog.file_selected.connect(func(_filepath): _file_task_dialog_open = false)
	
	#Engine.get_main_loop().root.add_child(file_dialog)
	file_dialog.popup_exclusive_centered(parent_node, Vector2i(800, 600))

	return file_dialog

static func confirm_dialog(title: String, body: String, confirm: String, cancel: String) -> bool:
	var dialog: ConfirmationDialog = ConfirmationDialog.new()
	dialog.title = "Sample Dialog"
	dialog.dialog_text = "Sample Dialog. Are you cool?"
	dialog.ok_button_text = confirm
	dialog.cancel_button_text = cancel
	var pc: Signal = Signal()
	dialog.confirmed.connect(func():
		pc.emit(true)
	)
	dialog.canceled.connect(func():
		pc.emit(false)
	)
	dialog.close_requested.connect(func(): dialog.queue_free())
	Engine.get_main_loop().get_root().add_child(dialog)
	dialog.popup_centered()
	
	return await pc
