extends MarginContainer

## Neovim ui docs state that there is only ever one 
## grid index passed to grid events, 1 the global grid
# NOTE: an option in the future might be to have an "ext_multigrid" toggle that 
# will split the windows into their own separate windows. So these variables are unchanged for now
var grid_index: int = 1
var grid_width: int
var grid_height: int

var cwd: String

@export_file_path() var path_to_nvim: String = "/usr/bin/nvim"
@onready var client = $NeovimClient
@onready var wm = $WindowManager

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if OS.is_debug_build():
		_initialize_todos()
	
	if _is_standalone():
		var r = get_tree().root
		assert(r.size.x == size.x and r.size.y == size.y)
		r.size_changed.connect(_on_standalone_resized)
	
	client.spawn(path_to_nvim)
	await get_tree().create_timer(.5).timeout
	setup_ui()

var _attached := false
func setup_ui():
	assert(not _attached)
	assert(client.is_running())
	var initial_size := get_editor_grid_size(wm.size)
	_attached = client.attach(initial_size.x, initial_size.y)

# checks if vimdow is the standalone app or the editor plugin
func _is_standalone() -> bool:
	return get_parent() is Window

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
				redraw_batch.push_back(event)


func _on_neovim_client_neovim_response(msgid: int, error: Variant, result: Variant) -> void:
	#print("msgid: %d, error: %s, result: %s" % [msgid, str(error), str(result)])
	pass

func _grid_assert(grid: int):
	assert(grid == grid_index, "Shouldn't receive an index for a different grid")

#region REDRAW_EVENTS
var redraw_batch: Array = []
func flush():
	#assert(not hl.is_empty())
	var  i := 0
	var dbg = OS.is_debug_build()
	while not redraw_batch.is_empty():
		var event: Array = redraw_batch.pop_front()
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
	if OS.is_debug_build(): 
		_redraw_events.store_line("###FLUSHED###")
		_redraw_events.flush()
		_log_options()
	
	for w in wm.get_children():
		assert(not hl.is_empty())
		w.flush(hl)

var hl := {}
func default_colors_set(rgb_fg: int, rgb_bg: int, rgb_sp: int, _cterm_fg, cterm_bg):
	hl[0] = {
		foreground = rgb_fg,
		background = rgb_bg,
		special = rgb_sp
	}

func hl_attr_define(id: int, rgb_attr: Dictionary, 
	_cterm_attr: Dictionary, _info: Array):
	hl[id] = rgb_attr

var hl_groups := {}
func hl_group_set(group_name: String, hl_id: int):
	hl_groups[group_name] = hl_id

var mode_info: Array
func mode_info_set(cursor_style_enabled: bool, mode_info: Array):
	# can't really see a case where it'd need to be false
	assert(cursor_style_enabled)
	self.mode_info = mode_info

var mode: String
var mode_idx: int
func mode_change(mode: String, mode_idx: int):
	self.mode = mode
	self.mode_idx = mode_idx
	
	var m: Dictionary = mode_info[self.mode_idx]
	for w: VimdowWindow in wm.get_children():
		w.cursor_shape = m.get("cursor_shape", w.cursor_shape)
func set_title(title: String):
	if _is_standalone():
		get_tree().root.title = title

func set_icon(icon: String):
	if _is_standalone():
		var r = get_tree().root
		r.title = r.title.insert(0, icon + " ")

func chdir(dir: String):
	cwd = dir

var _row_wraps: Array
func grid_resize(grid: int, width: int, height: int):
	_grid_assert(grid)
	grid_width = width
	grid_height = height
	_row_wraps = []
	for _i in height:
		_row_wraps.append(false)
	if wm.get_child_count() == 0:
		var new_win := VimdowWindow.new()
		wm.add_child(new_win)
		new_win.set_grid_size(width, height)
	else:
		var win: VimdowWindow = wm.get_child(0)
		win.set_grid_size(width, height)

# this shouldn't be sent if ext_multigrid == false.
# might be a bug but have this to just get it out of logs 
func win_viewport(_grid: int, _win: int, _topline: int, _botline: int, 
	_curline: int, _curcol: int, _line_count: int, _scroll_delta: int):
	return

var _last_hl_id: int
func grid_line(grid: int, row: int, col_start: int, cells: Array, wrapline: bool):
	_grid_assert(grid)
	var win: VimdowWindow = wm.get_child(0)
	_row_wraps[row] = wrapline
	
	var old_line = win.get_line(row)
	var line = old_line.substr(0, col_start)
	var hl_cols := {}
	var start = -1
	for cell in cells:
		# TODO: implement highlights
		start = line.length()
		match cell:
			[var text, var hl_id, var repeat]:
				line += text.repeat(repeat)
				_last_hl_id = hl_id
			[var text, var hl_id]:
				line += text
				_last_hl_id = hl_id
			[var text]:
				line += text
		assert(hl.has(_last_hl_id))
		hl_cols[start] = _last_hl_id
	
	win.clear_hl_region(row, start, line.length())
	line += old_line.substr(line.length())
	for col in hl_cols:
		win.insert_hl_column(row, col, hl_cols[col])
	win.set_line(row, line)

func grid_clear(grid: int):
	_grid_assert(grid)
	for w: VimdowWindow in wm.get_children():
		w.clear()

func grid_cursor_goto(grid: int, row: int, col: int):
	_grid_assert(grid)
	var win: VimdowWindow = wm.get_child(0)
	win.cursor.x = col
	win.cursor.y = row

func grid_scroll(grid: int, top: int, bot: int, 
	left: int, right: int, rows: int, cols: int):
	_grid_assert(grid)
	
	var w: VimdowWindow = wm.get_child(0)
	
	var lines := []
	for i in range(top, bot):
		lines.append(w.get_line(i))
	
	var dst_top := top - rows
	var dst_bot := bot - rows
	for i in range(dst_top, dst_bot):
		w.set_line(i, lines.pop_front())

#region OPTION_SET
var options := {}
func option_set(opt_name: String, value: Variant):
	options[opt_name] = value
#endregion OPTION_SET

#endregion REDRAW_EVENTS

#region NEOVIM_IMPL_TRACKER
var _redraw_events
var _option_set
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
#endregion


func _on_window_manager_resized() -> void:
	if not is_node_ready() or not _attached:
		return
	var s := get_editor_grid_size(wm.size)
	client.request("nvim_ui_try_resize", [s.x, s.y])

#region STANDALONE_METHODS
func _on_standalone_resized():
	if not (is_node_ready() or _attached):
		return
	#size = get_tree().root.size
	set_deferred("size", get_tree().root.size)
#endregion
