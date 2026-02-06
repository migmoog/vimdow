extends Control

@export_file_path() var path_to_nvim: String = "/usr/bin/nvim"
@onready var client = $NeovimClient

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	client.spawn(path_to_nvim)
	await get_tree().create_timer(1.5).timeout
	assert(client.is_running())
	client.attach(500, 200)

func _on_neovim_client_neovim_event(method: String, params: Array) -> void:
	print("%s: %s" % [method, str(params)])


func _on_neovim_client_neovim_response(msgid: int, error: Variant, result: Variant) -> void:
	print("msgid: %d, error: %s, result: %s" % [msgid, str(error), str(result)])
