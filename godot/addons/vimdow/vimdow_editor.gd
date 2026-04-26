@tool
class_name VimdowEditor
extends MarginContainer

## Neovim ui docs state that there is only ever one
## grid index passed to grid events, 1 the global grid
# NOTE: an option in the future might be to have an "ext_multigrid" toggle that 
# will split the windows into their own separate windows. So these variables are unchanged for now
var grid_index: int = 1
var grid_width: int
var grid_height: int
var mode: String
var mode_idx: int
var mode_info: Array
var hl := {}
var hl_groups := {}
var options := {}
var cwd: String

@export_file_path() var startup_script: String
@onready var client: NeovimClient = $NeovimClient
@onready var w = $VimdowWindow

## The viewport that the editor obeys the size of
var viewport_lock: Window
var attached := false

var _row_wraps: Array
var _redraw_batch := []
var _inputs_buffer: Array[InputEventKey] = []
var _mouse_buffer: Array[InputEvent] = []
var _redraw_events
var _option_set

## Configuration Handling ##
const MAIN_SECTION = "neovim"
const THEME_SECTION = "theme"
var _conf_path: String
var _conf: ConfigFile


#region SHORTCUTS
var increase_fontsize_shortcut: Shortcut
var decrease_fontsize_shortcut: Shortcut
#endregion

func _init() -> void:
	increase_fontsize_shortcut = Shortcut.new()
	decrease_fontsize_shortcut = Shortcut.new()
	
	var ifev = InputEventKey.new()
	ifev.ctrl_pressed = true
	ifev.keycode = KEY_EQUAL
	increase_fontsize_shortcut.events = [ifev]
	
	var dfev = InputEventKey.new()
	dfev.ctrl_pressed = true
	dfev.keycode = KEY_MINUS
	decrease_fontsize_shortcut.events = [dfev]


func _ready() -> void:
	_conf = ConfigFile.new()
	if _is_standalone():
		_conf_path = (
			OS.get_environment("VIMDOW_CONFIG_PATH") 
			if OS.has_environment("VIMDOW_CONFIG_PATH") else
			"user://vimdow.cfg"
		)
		if _conf.load(_conf_path) != OK:
			_conf.set_value(MAIN_SECTION, "path_to_nvim", "/usr/bin/nvim")
		call_deferred("start")
	else:
		_conf.set_value(MAIN_SECTION, "path_to_nvim", ProjectSettings.get_setting("vimdow/path_to_nvim"))
		var ei = _get_editor_interface()
		var es = ei.get_editor_settings()
		es.add_shortcut("vimdow/increase_font_size", increase_fontsize_shortcut)
		es.add_shortcut("vimdow/decrease_font_size", decrease_fontsize_shortcut)
		$ColorRect.color = es.get_setting("interface/theme/base_color")

func _exit_tree() -> void:
	if not _is_standalone():
		var es = _get_editor_interface().get_editor_settings()
		es.remove_shortcut("vimdow/increase_font_size")
		es.remove_shortcut("vimdow/decrease_font_size")

func start() -> void:
	if ProjectSettings.get_setting("vimdow/debug/log_msgpack"):
		_initialize_todos()
		client.neovim_response.connect(self._log_responses)
	
	if _is_standalone():
		var r = get_tree().root
		assert(r.size.x == size.x and r.size.y == size.y)
		
		# ConfigFile theme options
		if _conf.has_section_key(THEME_SECTION, "font_size"):
			var fs = _conf.get_value(THEME_SECTION, "font_size")
			theme.set_font_size("font_size", "VimdowEditor", fs)

		for font_property in ["bold", "italic", "normal"]:
			if _conf.has_section_key(THEME_SECTION, font_property):
				var path_from_conf = _conf.get_value(THEME_SECTION, font_property)
				var path = _conf_path.get_base_dir().path_join(path_from_conf).simplify_path()

				if not FileAccess.file_exists(path):
					push_error("No font file '%s'" % path)
					continue
				var font_file := FontFile.new()
				var bytes = FileAccess.get_file_as_bytes(path)
				font_file.data = bytes

				theme.set_font(
					font_property,
					"VimdowEditor",
					font_file
				)

		lock_to_window(r)
	else:
		OS.set_environment("GODOT_LANGSERVER_PORT", str(_get_editor_interface()\
			.get_editor_settings()\
			.get_setting("network/language_server/remote_port")))

		OS.set_environment("GODOT_VERSION", Engine.get_version_info().string)
	
	var args := PackedStringArray(["--embed"])
	if not _is_standalone():
		args.append_array([
			"-S",
			ProjectSettings.globalize_path(startup_script),
		])
	args.append_array(OS.get_cmdline_user_args())

	client.spawn(_conf.get_value(MAIN_SECTION, "path_to_nvim"), args)
	await get_tree().create_timer(.1).timeout
	assert(client.is_running())
	var initial_size := get_editor_grid_size(w.size)
	# attached = client.attach(initial_size.x, initial_size.y)
	client.request("nvim_ui_attach", [initial_size.x, initial_size.y, {
		"ext_linegrid" : true,
		"rgb" : true,
	}])
	attached = true # may come up with a better way to assert this
	
	var file = ProjectSettings.get_setting("vimdow/edit_file")
	if file:
		open_file(file)


func _acceptable_key(e: InputEvent) -> bool:
	return attached and visible\
			and (e is InputEventKey and e.is_pressed())

func _acceptable_mouse(e: InputEvent) -> bool:
	return attached and visible\
			and e is InputEventMouse


func _gui_input(event: InputEvent) -> void:
	if _acceptable_key(event):
		get_viewport().set_input_as_handled()
		if increase_fontsize_shortcut.matches_event(event):
			theme.set_font_size("font_size", "VimdowEditor", theme.get_font_size("font_size", "VimdowEditor") + 1)
			try_resize()
		elif decrease_fontsize_shortcut.matches_event(event):
			theme.set_font_size("font_size", "VimdowEditor", theme.get_font_size("font_size", "VimdowEditor") - 1)
			try_resize()
		else:
			_inputs_buffer.append(event)
	elif _acceptable_mouse(event):
		_mouse_buffer.append(event)


func _process(_delta: float) -> void:
	if attached:
		if not _inputs_buffer.is_empty():
			client.flush_key_inputs(_inputs_buffer)
		
		if not _mouse_buffer.is_empty():
			var char_size := get_theme_font("normal", "VimdowEditor")\
				.get_char_size(ord(' '), get_theme_font_size("font_size", "VimdowEditor"))
			client.flush_mouse_inputs(
				grid_index,
				_mouse_buffer,
				get_theme_font("normal", "VimdowEditor")\
						.get_char_size(ord(" "), get_theme_font_size("font_size", "VimdowEditor")),
			)

## NOTE: This method exists because the export crashes from parse errors
## when EditorInterface is not present
func _get_editor_interface():
	return Engine.get_singleton("EditorInterface")

func quit(code: int):
	if _is_standalone():
		get_tree().quit()
	else:
		if code != 0:
			push_warning("Neovim quit with code: %d" % code)
		$VimdowWindow.visible = false
		$ButtonContainer.visible = true
		attached = false


# checks if vimdow is the standalone app or the editor plugin
func _is_standalone() -> bool:
	return not Engine.is_editor_hint() and DisplayServer.get_name() != "headless"


func get_editor_grid_size(s: Vector2) -> Vector2i:
	var font_size = theme.get_font_size("font_size", "VimdowEditor")
	var char_size: Vector2 = theme.get_font("normal", "VimdowEditor")\
		.get_char_size(ord(" "), font_size)
	return Vector2i((s/char_size).floor())


func _on_neovim_client_neovim_event(method: String, params: Array) -> void:
	if method == "redraw":
		for event in params:
			var event_name: String = event[0]
			if event_name == "flush":
				flush()
			else:
				_redraw_batch.push_back(event)


func _on_neovim_client_neovim_request(msgid: int, method: String, _params: Array) -> void:
	if method.lstrip('"').rstrip('"') == "release_focus":
		release_focus()
		client.respond(msgid, null, null)

func _grid_assert(grid: int):
	assert(grid == grid_index, "Shouldn't receive an index for a different grid")


#region NEOVIM_COMMANDS

## checks the size of the control and requests neovim to try and resize
func try_resize() -> void:
	if not is_node_ready() or not attached:
		return
	var s := get_editor_grid_size(w.size)
	client.request("nvim_ui_try_resize", [s.x, s.y])

## Opens a file in vimdow
func open_file(path: String, line: int = -1):
	if attached:
		var cmd = ("e +%d " % line if line > 0 else "e ") + path
		client.request("nvim_command", [cmd])

## Instructs the lua plugin to clear all breakpoints. Can optionally specify the buffer to clear
func clear_breakpoints(path = ""):
	assert(attached)
	client.request("nvim_command", [ "VimdowClearBreakpoints " + path ])

## Instructs the lua plugin to set the value of a breakpoint
func set_breakpoint(path: String, line: int, enabled: bool):
	assert(attached)
	var command_str = "lua Vimdow.set_breakpoint(\"%s\", %d, %s, true)" % [path, line, enabled]
	client.request("nvim_command", [ command_str ])

#endregion

#region REDRAW_EVENTS
func flush():
	var  i := 0
	var dbg = ProjectSettings.get_setting("vimdow/debug/log_msgpack")
	while not _redraw_batch.is_empty():
		var event: Array = _redraw_batch.pop_front()
		var event_name: String = event.pop_front()
		if has_method(event_name):
			for e in event:
				callv(event_name, e)
		elif dbg:
			_redraw_events.store_line("[%d] %s: %s" %[
				i,
				event_name, 
				JSON.stringify(event)])
		i += 1
	if dbg: 
		_redraw_events.store_line("###FLUSHED###")
		_redraw_events.flush()
		_log_options()
	
	assert(not hl.is_empty())
	w.flush(hl, mode_info[mode_idx])


static func rgb_to_color(rgb: int) -> Color:
	return Color(
		((rgb >> 16) & 0xFF) / 255.0,
		((rgb >> 8) & 0xFF) / 255.0,
		(rgb & 0xFF) / 255.0,
		1.0
	)


func _add_hl(hl_id:int, attr: Dictionary):
	for color_attr in ["foreground", "background", "special"]:
		if attr.has(color_attr):
			attr[color_attr] = rgb_to_color(attr[color_attr])
	
	hl[hl_id] = attr


func default_colors_set(rgb_fg: int, rgb_bg: int, rgb_sp: int, _cterm_fg, _cterm_bg):
	_add_hl(0, {
		foreground = rgb_fg,
		background = rgb_bg,
		special = rgb_sp
	})
	
	$ColorRect.color = hl[0].background

func hl_attr_define(id: int, rgb_attr: Dictionary, 
	_cterm_attr: Dictionary, _info: Array):
	_add_hl(id, rgb_attr)


func hl_group_set(group_name: String, hl_id: int):
	hl_groups[hl_id] = group_name


func mode_info_set(cursor_style_enabled: bool, mode_info: Array):
	# can't really see a case where it'd need to be false
	assert(cursor_style_enabled)
	self.mode_info = mode_info


func mode_change(mode: String, mode_idx: int):
	self.mode = mode
	self.mode_idx = mode_idx


func set_title(title: String):
	if viewport_lock:
		viewport_lock.title = title


func set_icon(icon: String):
	if _is_standalone():
		var r = get_tree().root
		r.title = r.title.insert(0, icon + " ")


func chdir(dir: String):
	cwd = dir


func grid_resize(grid: int, width: int, height: int):
	_grid_assert(grid)
	grid_width = width
	grid_height = height
	_row_wraps = []
	for _i in height:
		_row_wraps.append(false)
	w.set_grid_size(width, height)


# this shouldn't be sent if ext_multigrid == false.
# might be a bug but have this to just get it out of logs 
func win_viewport(_grid: int, _win: int, _topline: int, _botline: int, 
	_curline: int, _curcol: int, _line_count: int, _scroll_delta: int):
	return


func grid_line(grid: int, row: int, col_start: int, cells: Array, wrapline: bool):
	_grid_assert(grid)
	_row_wraps[row] = wrapline
	var old_line = w.get_line(row)
	var line = old_line.substr(0, col_start)
	var last_hl_id = null
	var col_end = col_start
	var regions = $VimdowWindow/Highlighter.hl_regions[row]
	for cell in cells:
		var col = col_end
		match cell:
			[var text, var hl_id, var repeat]:
				line += text.repeat(repeat)
				col_end += repeat
				last_hl_id = hl_id
				for i in repeat:
					regions[col + i] = last_hl_id
			[var text, var hl_id]:
				line += text
				col_end += 1
				last_hl_id = hl_id
				regions[col] = last_hl_id
			[var text]:
				line += text
				col_end += 1
				regions[col] = last_hl_id
		assert(hl.has(last_hl_id))
	
	line += old_line.substr(line.length())
	w.set_line(row, line)


func grid_clear(grid: int):
	_grid_assert(grid)
	w.clear()


func grid_cursor_goto(grid: int, row: int, col: int):
	_grid_assert(grid)
	w.cursor.x = col
	w.cursor.y = row


func grid_scroll(grid: int, top: int, bot: int, 
	left: int, right: int, rows: int, _cols: int):
	_grid_assert(grid)
	
	var lines := []
	var hl_regions := []
	for i in range(top, bot):
		lines.append(w.get_line(i))
		hl_regions.append($VimdowWindow/Highlighter.hl_regions[i].duplicate())
	
	var dst_top := top - rows
	var dst_bot := bot - rows
	
	for row in range(dst_top, dst_bot):
		var src_line = lines.pop_front()
		var src_regions = hl_regions.pop_front()
		if row < top or row >= bot:
			continue
		var dst_line = w.get_line(row)
		var line = dst_line.substr(0, left) + src_line.substr(left, right - left) + dst_line.substr(right)
		w.set_line(row, line)
		for i in range(left, right):
			$VimdowWindow/Highlighter.hl_regions[row][i] = src_regions[i]


#region OPTION_SET
func option_set(opt_name: String, value: Variant):
	options[opt_name] = value
#endregion OPTION_SET

#endregion REDRAW_EVENTS

#region DEBUG_INFO
func _initialize_todos():
	const TODOS_PATH = "res://../nvim_todos"
	if not DirAccess.dir_exists_absolute(TODOS_PATH):
		DirAccess.make_dir_absolute(TODOS_PATH)
	_redraw_events  = FileAccess.open(TODOS_PATH.path_join("redraw_events.txt"), FileAccess.WRITE)
	_option_set = FileAccess.open(TODOS_PATH.path_join("option_set.json"), FileAccess.WRITE)


func _log_options():
	_option_set.store_string(JSON.stringify(
		options, 
		"\t", 
		false, 
		true
	) + ",\n\n")
	_option_set.flush()


func _log_responses(msgid: int, error: Variant, result: Variant) -> void:
	print("msgid: %d, error: %s, result: %s" % [msgid, str(error), str(result)])
#endregion



## Forces the editor to follow the same size
## as the viewport holding it and add it as a child
func lock_to_window(v: Window):
	assert(not get_parent() is Container, 
			"Cannot resize while attached to a container")
	assert(v.is_ancestor_of(self),
			"Editor must be child of the viewport its locked to")
	assert(viewport_lock == null,
			"Editor can only lock to one viewport at a time")
	viewport_lock = v
	v.size_changed.connect(_on_viewport_lock_size_changed)
	_on_viewport_lock_size_changed()


## Removes the editor from the current viewport its locked to
## and unattach its size change signal
func unlock_from_window():
	assert(viewport_lock != null, 
			"Not locked to any viewport")
	viewport_lock.size_changed.disconnect(_on_viewport_lock_size_changed)
	viewport_lock = null


func _on_viewport_lock_size_changed():
	assert(viewport_lock != null)
	if not (is_node_ready() or attached):
		return
	set_deferred("size", viewport_lock.size)


func _on_restart_button_pressed() -> void:
	$ButtonContainer.visible = false
	$VimdowWindow.visible = true
	call_deferred("start")
