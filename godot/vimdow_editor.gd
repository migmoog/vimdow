extends Control

@export_file_path() var path_to_nvim: String = "/usr/bin/nvim"
@onready var client = $NeovimClient

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if OS.is_debug_build():
		_initialize_todos()
	
	client.spawn(path_to_nvim)
	await get_tree().create_timer(1.5).timeout
	assert(client.is_running())
	client.attach(500, 200)


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


#region REDRAW_EVENTS
var redraw_batch: Array = []
func flush():
	while not redraw_batch.is_empty():
		var event: Array = redraw_batch.pop_front()
		var event_name: String = event.pop_front()
		if has_method(event_name):
			for e in event:
				call(event_name, e)
		elif OS.is_debug_build():
			_redraw_events.store_line(event_name)
	if OS.is_debug_build(): 
		_redraw_events.store_line("###FLUSHED###")
		_redraw_events.flush()
#endregion

#region NEOVIM_IMPL_TRACKER
var _redraw_events
func _initialize_todos():
	const TODOS_PATH = "res://../nvim_todos"
	if not DirAccess.dir_exists_absolute(TODOS_PATH):
		DirAccess.make_dir_absolute(TODOS_PATH)
	_redraw_events  = FileAccess.open(TODOS_PATH.path_join("redraw_events.txt"), FileAccess.WRITE)
#endregion
