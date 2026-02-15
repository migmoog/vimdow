@tool
extends Control
class_name TROnboardingPanel

var runner: TRTaskRunner

func _ready() -> void:
	var bg_panel: StyleBoxFlat = %PanelContainer.get_theme_stylebox("panel")
	bg_panel.bg_color = get_theme_color("base_color", "Editor")
	%PanelContainer.add_theme_stylebox_override("panel", bg_panel)
	
	%OnboardingLabel.meta_clicked.connect(func(meta: Variant):
		if meta == "DOCS_LINK":
			OS.shell_open(TRTaskRunner.DOCS_LINK)
	)
	
	%AddSampleTasks.pressed.connect(add_sample_tasks)

func add_sample_tasks():
	runner.bootstrap_inline_task_from_file("BASH", "Sample - Bash", "res://addons/TaskRunner/Examples/SampleTasks/bash_sample.sh")
	runner.bootstrap_inline_task_from_file("CMD", "Sample - cmd.exe", "res://addons/TaskRunner/Examples/SampleTasks/batch_sample.cmd")
	runner.bootstrap_inline_task_from_file("POWERSHELL", "Sample - Powershell", "res://addons/TaskRunner/Examples/SampleTasks/powershell_sample.ps1")
	runner.bootstrap_inline_task_from_file("NEW_PROCESS_GDSCRIPT", "Sample - GDScript", "res://addons/TaskRunner/Examples/SampleTasks/gdscript_sample.gd")
	runner.bootstrap_inline_task_from_file("NEW_PROCESS_GDSCRIPT", "Sample - Message Passing", "res://addons/TaskRunner/Examples/SampleTasks/message_passing_sample.gd")
	runner.bootstrap_inline_task_from_file("IN_EDITOR_GDSCRIPT", "Sample - Debug Games", "res://addons/TaskRunner/Examples/SampleTasks/debug_games_sample.gd")
	runner.bootstrap_inline_task_from_file("IN_EDITOR_GDSCRIPT", "Sample - Subtask Management", "res://addons/TaskRunner/Examples/SampleTasks/subtask_management_sample.gd")
	runner.bootstrap_inline_task_from_file("IN_EDITOR_GDSCRIPT", "Sample - Editor Popup", "res://addons/TaskRunner/Examples/SampleTasks/editor_popup_sample.gd")
	
	runner.bootstrap_task_file("IN_EDITOR_GDSCRIPT", "Sample - On Disk Task", "res://addons/TaskRunner/Examples/SampleTasks/on_disk_task_sample.gd")
