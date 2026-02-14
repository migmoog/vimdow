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
	
	if get_parent() is Window:
		var r = get_tree().root
		assert(r.size.x == size.x and r.size.y == size.y)
		r.size_changed.connect(_on_standalone_resized)
	
	client.spawn(path_to_nvim)
	await get_tree().create_timer(.1).timeout
	setup_ui()

var _attached := false
func setup_ui():
	assert(not _attached)
	assert(client.is_running())
	var initial_size := get_editor_grid_size(wm.size)
	client.attach(initial_size.x, initial_size.y)

func get_editor_grid_size(s: Vector2) -> Vector2i:
	var font_size = theme.get_font_size("font_size", "CodeEdit")
	var char_size: Vector2 = theme.get_font("font", "CodeEdit").get_char_size(ord(" "), font_size)
	return Vector2i((s/char_size).floor())

func _on_neovim_client_neovim_event(method: String, params: Array) -> void:
	if method == "redraw":
		for event in params:
			var event_name: String = event[0]
			if event_name == "flush":
				flush()
			else:
				redraw_batch.push_back(event)


func _on_neovim_client_neovim_response(msgid: int, error: Variant, result: Variant) -> void:
	print("msgid: %d, error: %s, result: %s" % [msgid, str(error), str(result)])

func _grid_assert(grid: int):
	assert(grid == grid_index, "Shouldn't receive an index for a different grid")

#region REDRAW_EVENTS
var redraw_batch: Array = []
func flush():
	while not redraw_batch.is_empty():
		var event: Array = redraw_batch.pop_front()
		var event_name: String = event.pop_front()
		if has_method(event_name):
			for e in event:
				callv(event_name, e)
		elif OS.is_debug_build():
			_redraw_events.store_line(event_name)
	if OS.is_debug_build(): 
		_redraw_events.store_line("###FLUSHED###")
		_redraw_events.flush()
		_log_options()

func chdir(dir: String):
	cwd = dir

func grid_resize(grid: int, width: int, height: int):
	_grid_assert(grid)
	grid_width = width
	grid_height = height
	if wm.get_child_count() == 0:
		var new_win := VimdowWindow.new()
		wm.add_child(new_win)
		new_win.set_grid_size(width, height)
	else:
		var win: VimdowWindow = wm.get_child(0)
		win.set_grid_size(width, height)

var _last_hl_id: int
func grid_line(grid: int, row: int, col_start: int, cells: Array, wrap: bool):
	_grid_assert(grid)
	var win: VimdowWindow = wm.get_child(0)
	var line = win.get_line(row).substr(0, col_start)
	for cell in cells:
		# TODO: implement highlights
		match cell:
			[var text, var hl_id, var repeat]:
				line += text.repeat(repeat)
				_last_hl_id = hl_id
			[var text, var hl_id]:
				line += text
				_last_hl_id = hl_id
			[var text]:
				line += text
	while line.length() < grid_width: 
		line += " "
	win.set_line(row, line)

func grid_clear(grid: int):
	_grid_assert(grid)
	for w: VimdowWindow in wm.get_children():
		w.clear()

func grid_cursor_goto(grid: int, row: int, col: int):
	_grid_assert(grid)
	var win: VimdowWindow = wm.get_child(0)
	win.set_cursor(col, row)

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
	if not (is_node_ready() or _attached):
		return
	var s := get_editor_grid_size(wm.size)
	client.request("nvim_ui_try_resize", [s.x, s.y])

#region STANDALONE_METHODS
func _on_standalone_resized():
	if not (is_node_ready() or _attached):
		return
	# FIXME: scales to the innards of the window
	print_debug("Original size: ", size)
	size = get_tree().root.size
	print_debug("Window size: ", size)
#endregion
