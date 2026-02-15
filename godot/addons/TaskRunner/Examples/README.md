# Task Runner Examples

This folder contains example demonstrating how to use the task runner.

## SampleTasks

The SampleTasks folder contains examples of valid Task Runner tasks.
If no other tasks are registered in your project, the Task Runner will show a prompt offering to register the sample tasks.

### Basic Samples

These tasks demonstrate basic functionality in each supported language.

* [SampleTasks/bash_sample.sh](./SampleTasks/bash_sample.sh)
* [SampleTasks/batch_sample.cmd](SampleTasks/batch_sample.cmd)
* [SampleTasks/powershell_sample.ps1](SampleTasks/powershell_sample.ps1)
* [SampleTasks/gdscript_sample.gd](SampleTasks/gdscript_sample.gd)

### Message Passing

This task demonstrates how to send a structured json message from a child task up to it's parent.

* [SampleTasks/message_passing_sample.gd](SampleTasks/message_passing_sample.gd)

### Launch and Debug a Game

This sample shows how to start your game in a background process and automatically connect the debugger to it.
It also shows how to pass arguments into your game. Useful for spawning multiple game clients and configuring them each differently.

There are also two sample scenes that are started by the sample script.

* [SampleTasks/debug_games_sample.gd](SampleTasks/debug_games_sample.gd)
* [SampleScenes/sample_scene_1.gd](SampleScenes/sample_scene_1.gd), [SampleScenes/sample_scene_1.tscn](SampleScenes/sample_scene_1.tscn)
* [SampleScenes/sample_scene_2.gd](SampleScenes/sample_scene_2.gd), [SampleScenes/sample_scene_2.tscn](SampleScenes/sample_scene_2.tscn)

### Managing Subtasks

This sample shows how to manage subtasks from a parent gdscript task. It covers:
* Running subtasks in parallel and serial
* Canceling subtasks
* Creating subtasks without starting them
* Creating anonymous subtasks
#####
* [SampleTasks/subtask_management_sample.gd](SampleTasks/subtask_management_sample.gd)

### Editor Popup Sample

This sample shows how to spawn a confirmation dialog from a task. This could be useful to prompt for human input as part of a task run.
It's also a good example of in editor tasks are able to interact with the editor itself.

* [SampleTasks/editor_popup_sample.gd](SampleTasks/editor_popup_sample.gd)

### On Disk Sample

This is a very simple "hello world" task. If you load it via the onboarding page, it will be added as an on disk task.

* [SampleTasks/on_disk_task_sample.gd](SampleTasks/on_disk_task_sample.gd)

## Bootstrapping Tasks

This script shows how to check if the Task Runner exists and register new tasks with it in a type safe, nondestructive way.

Why would you want to do this? Imagine you're writing a new plugin and you want that plugin to add some scripts to the Task Runner.
For example, you're writing a multiplayer tool and you want to automatically add a "deploy server" script to the Task Runner.
This script shows how to check if the Task Runner exists, and add your script only if it doesn't already exist.

Note that best practices don't really exist around this yet. Try your best not to step on anybodies toes if your going to automatically
add new tasks to your user's project.

* [BootstrapTasks.gd](BootstrapTasks.gd)
