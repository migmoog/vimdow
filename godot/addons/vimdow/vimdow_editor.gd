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
@onready var client = $NeovimClient
@onready var w = $VimdowWindow

var attached := false

var _row_wraps: Array
var _redraw_batch := []
var _inputs_buffer: Array[InputEventKey] = []
var _mouse_buffer: Array[InputEvent] = []
var _redraw_events
var _option_set


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
	if _is_standalone():
		call_deferred("start")
	else:
		var es := EditorInterface.get_editor_settings()
		es.add_shortcut("vimdow/increase_font_size", increase_fontsize_shortcut)
		es.add_shortcut("vimdow/decrease_font_size", decrease_fontsize_shortcut)

func _exit_tree() -> void:
	if not _is_standalone():
		var es := EditorInterface.get_editor_settings()
		es.remove_shortcut("vimdow/increase_font_size")
		es.remove_shortcut("vimdow/decrease_font_size")

func start() -> void:
	if ProjectSettings.get_setting("vimdow/debug/log_msgpack"):
		_initialize_todos()
		client.neovim_response.connect(self._log_responses)
	
	if _is_standalone():
		var r = get_tree().root
		assert(r.size.x == size.x and r.size.y == size.y)
		r.size_changed.connect(_on_standalone_resized)
	else:
		OS.set_environment("GODOT_LANGSERVER_PORT", str(EditorInterface.get_editor_settings().get_setting("network/language_server/remote_port")))
	
	var args: Array[String] = [
		"--embed",
		"-S",
		ProjectSettings.globalize_path(startup_script),
	]
	client.spawn(ProjectSettings.get_setting("vimdow/path_to_nvim"), args)
	await get_tree().create_timer(.1).timeout
	setup_ui()
	
	var file = ProjectSettings.get_setting("vimdow/edit_file")
	if file:
		open_file(file)


func _acceptable_key(e: InputEvent) -> bool:
	return attached and visible\
			and (e is InputEventKey and e.is_pressed())

func _acceptable_mouse(e: InputEvent) -> bool:
	return attached and visible\
			and (
				e is InputEventMouse
				)

func _input(event: InputEvent) -> void:
	if _acceptable_key(event):
		get_viewport().set_input_as_handled()
		if increase_fontsize_shortcut.matches_event(event):
			theme.set_font_size("font_size", "VimdowEditor", theme.get_font_size("font_size", "VimdowEditor") + 1)
			_on_window_resized()
		elif decrease_fontsize_shortcut.matches_event(event):
			theme.set_font_size("font_size", "VimdowEditor", theme.get_font_size("font_size", "VimdowEditor") - 1)
			_on_window_resized()
		else:
			_inputs_buffer.append(event)
	elif _acceptable_mouse(event):
		_mouse_buffer.append(event)


func _process(_delta: float) -> void:
	if attached:
		if not _inputs_buffer.is_empty():
			client.flush_key_inputs(_inputs_buffer)
		elif not _mouse_buffer.is_empty():
			var char_size := get_theme_font("normal", "VimdowEditor")\
				.get_char_size(ord(' '), get_theme_font_size("font_size", "VimdowEditor"))
			client.flush_mouse_inputs(
				grid_index,
				_mouse_buffer,
				get_theme_font("normal", "VimdowEditor")\
						.get_char_size(ord(" "), get_theme_font_size("font_size", "VimdowEditor")),
				$Anchor,
			)


func quit(_code: int):
	if _is_standalone():
		get_tree().quit()
	else:
		EditorInterface.set_plugin_enabled("vimdow", false)


func setup_ui():
	assert(not attached)
	assert(client.is_running())
	var initial_size := get_editor_grid_size(w.size)
	attached = client.attach(initial_size.x, initial_size.y)


# checks if vimdow is the standalone app or the editor plugin
func _is_standalone() -> bool:
	return not Engine.is_editor_hint()


func get_editor_grid_size(s: Vector2) -> Vector2i:
	var font_size = theme.get_font_size("font_size", "VimdowEditor")
	var char_size: Vector2 = theme.get_font("normal", "VimdowEditor")\
		.get_char_size(ord(" "), font_size)
	return Vector2i((s/char_size).round())


func _on_neovim_client_neovim_event(method: String, params: Array) -> void:
	if method == "redraw":
		for event in params:
			var event_name: String = event[0]
			if event_name == "flush":
				flush()
			else:
				_redraw_batch.push_back(event)


func _grid_assert(grid: int):
	assert(grid == grid_index, "Shouldn't receive an index for a different grid")


## Opens a file in vimdow
func open_file(path: String):
	if attached:
		client.request("nvim_cmd", [{
			cmd = "e",
			args = [path]
		}, 
		{
			output = OS.is_debug_build()
		}])


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
	
	if _is_standalone():
		RenderingServer.set_default_clear_color(hl[0].background)


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
	if _is_standalone():
		get_tree().root.title = title


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
	pass
#endregion


func _on_window_resized() -> void:
	if not is_node_ready() or not attached:
		return
	var s := get_editor_grid_size(w.size)
	client.request("nvim_ui_try_resize", [s.x, s.y])

#region STANDALONE_METHODS
func _on_standalone_resized():
	if not (is_node_ready() or attached):
		return
	set_deferred("size", get_tree().root.size)
#endregion
