@tool
extends Window
class_name TRBugReportPopup

static func show_bugreport():
	var p: TRBugReportPopup = preload("res://addons/TaskRunner/Dock/BugReportPopup.tscn").instantiate()
	p.close_requested.connect(func():
		p.queue_free()
	)
	Engine.get_main_loop().get_root().add_child(p)
	p.popup_centered()
	

func _ready():
	var bg_panel: StyleBoxFlat = $PanelContainer.get_theme_stylebox("panel")
	bg_panel.bg_color = get_theme_color("base_color", "Editor")
	$PanelContainer.add_theme_stylebox_override("panel", bg_panel)
