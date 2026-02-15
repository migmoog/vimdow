@tool
extends Control
class_name TRDockTab

var side_panel: Control
var footer: Control
var tab_name: String

var dock: TRTaskRunnerDock
var runner: TRTaskRunner

signal on_focused
signal on_hidden
