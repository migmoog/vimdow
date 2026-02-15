@tool
extends Control
class_name TRTaskRunnerDock

var runner: TRTaskRunner

var task_tab: TRTasksTab = preload("res://addons/TaskRunner/Dock/TasksTab/MainPanel.tscn").instantiate()
var task_run_tab: TRTaskRunsTab = preload("res://addons/TaskRunner/Dock/TaskRunsTab/MainPanel.tscn").instantiate()

func _ready() -> void:
	if not runner: return
	
	task_tab = preload("res://addons/TaskRunner/Dock/TasksTab/MainPanel.tscn").instantiate()
	task_run_tab = preload("res://addons/TaskRunner/Dock/TaskRunsTab/MainPanel.tscn").instantiate()
	
	add_dock_tab(task_tab)
	add_dock_tab(task_run_tab)
	
	set_visible_tab(task_tab)
	%DockTabs.tab_changed.connect(func(idx):		
		set_visible_tab(get_tab_by_index(idx))
	)
	
	%BugReportButton.pressed.connect(func():
		TRBugReportPopup.show_bugreport()
	)
	
	%DocumentationButton.pressed.connect(func():
		OS.shell_open(TRTaskRunner.DOCS_LINK)
	)

func add_dock_tab(tab: TRDockTab):
	tab.dock = self
	tab.runner = runner
	%TaskMainPanelMount.add_child(tab)
	%TaskSidePanelMount.add_child(tab.side_panel)
	%TaskFooterMount.add_child(tab.footer)
	
	%DockTabs.add_tab(tab.tab_name)
	%DockTabs.reset_size()
	%SidePanel.custom_minimum_size.x = %DockTabs.size.x

func get_tab_by_name(tab_name: String) -> TRDockTab:
	for tab in %TaskMainPanelMount.get_children():
		if tab.tab_name == tab_name: return tab
	return null
	
func get_tab_by_index(tab_idx: int) -> TRDockTab:
	return get_tab_by_name(%DockTabs.get_tab_title(tab_idx))

func set_visible_tab(tab: TRDockTab):
	for idx in %DockTabs.tab_count:
		if %DockTabs.get_tab_title(idx) == tab.tab_name:
			%DockTabs.current_tab = idx
			break
			
	for c in %TaskMainPanelMount.get_children(): c.visible = false
	for c in %TaskSidePanelMount.get_children(): c.visible = false
	for c in %TaskFooterMount.get_children(): c.visible = false
	tab.visible = true
	tab.side_panel.visible = true
	tab.footer.visible = true
	for c in %TaskMainPanelMount.get_children():
		if c == tab:
			tab.on_focused.emit()
		else:
			c.on_hidden.emit()
