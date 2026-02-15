@tool
extends Node

# add this node to the scene tree and check the call_bootstrap_function box to call the sample bootstrap function
# In reality, you will likely call "bootstrap_task_ in a plugin.gd file.
@export var call_bootstrap_function: bool:
	set(value):
		if value and Engine.is_editor_hint():
			bootstrap_function()


func bootstrap_function():
	if EditorInterface.is_plugin_enabled("TaskRunner"):
		load("res://addons/TaskRunner/Core/TaskRunner.gd").bootstrap_task("IN_EDITOR_GDSCRIPT", "Example 1", 
			"""
func run(r: TRTaskRun):
	r.log("hello world")
	return "Success"
			""", true)
