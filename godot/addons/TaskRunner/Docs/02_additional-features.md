# Additional Features

Task Runner provides several additional features that enable more advanced workflows. This guide covers message passing, subtask spawning, anonymous tasks, and configuration options.

## Table of Contents

- [Message Passing](#message-passing)
    - [In GDScript Tasks](#in-gdscript-tasks)
    - [In Subprocess Tasks](#in-subprocess-tasks)
    - [Retrieving Messages from Subtasks](#retrieving-messages-from-subtasks)
    - [Checking Task Results](#checking-task-results)
- [Spawning Subtasks](#spawning-subtasks)
    - [Execution Patterns](#execution-patterns)
    - [Anonymous Tasks](#anonymous-tasks)
      - [Creating and Running Anonymous Tasks](#creating-and-running-anonymous-tasks)
- [Project Settings](#project-settings)
    - [Available Settings](#available-settings)
    - [How to Modify Settings](#how-to-modify-settings)
- [Running Tasks from the CLI](#running-tasks-from-the-cli)
    - [Supported Arguments](#supported-arguments)
    - [Known Issues](#known-issues)

## Message Passing

Tasks can return structured data to Task Runner, enabling communication between parent tasks and subtasks. This allows you to pass results from one task to another in a chain, return structured data for debugging, coordinate complex workflows with multiple subtasks, and collect aggregate results from parallel tasks.

### In GDScript Tasks

Use the `TRTaskRun.log_message()` method to send messages. Messages are typically dictionaries but can be any JSON-serializable type (arrays, strings, numbers, etc.).

For example:

```gdscript
func run(r: TRTaskRun):
    ...

    r.log_message({"build_status": "success"})
```

### In Subprocess Tasks

Use the `TRTASK_MESSAGE_PREFIX` prefix in your shell output to send structured data. You can customize this prefix in [Project Settings](#project-settings) if needed.

For example, in Bash tasks, you can return messages with the following:

```bash
echo 'TRTASK_MESSAGE_PREFIX {"build_status": "success"}'
```

### Retrieving Messages from Subtasks

Parent tasks can access messages from their subtasks in two ways:

- **Live Messages**: Connect to the `TRTask.on_message` signal to receive messages as they are emitted during subtask execution
- **All Messages**: Access the `messages` field (an array of `LogMessage` types) on a completed subtask run to retrieve all messages at once

The `LogMessage` type is defined in `addons/TaskRunner/Core/TaskRun.gd` if you need to reference its explicit definition.

### Checking Task Results

After a subtask completes, check its `end_status` variable (a `String`) to determine the exit code or return value of the task.

**For detailed examples**, see the [Examples directory](../Examples/README.md).

## Spawning Subtasks

GDScript tasks can spawn additional tasks dynamically, creating hierarchical execution trees for complex workflows. Subtasks can be run sequentially or in parallel, with full control over error handling and conditional execution.

### Execution Patterns

Task Runner supports multiple execution patterns for subtasks:

- **Sequential Execution**: Run tasks one after another, with each task starting only after the previous completes
- **Parallel Execution**: Spawn multiple tasks simultaneously and wait for all to complete
- **Conditional Execution**: Dynamically decide which tasks to run based on runtime conditions or previous task results
- **Error Handling**: Check `end_status` and respond to failures by running cleanup tasks or alternative workflows

Use `r.run_subtask("task-name")` to spawn a registered task by name, then `await subtask.await_end()` to wait for completion. Check results with `subtask.end_status` and retrieve messages from `subtask.messages` or by connecting to `subtask.on_message`.

### Anonymous Tasks

Anonymous tasks are temporary tasks that run as subtasks without being registered in the task list. This is useful for quick inline operations, dynamic task generation based on runtime data, temporary debugging, or one-off automation that doesn't belong in the permanent task list.

#### Creating and Running Anonymous Tasks

Use `r.run_anon_subtask()` to create and immediately run an anonymous task:

```gdscript
var subtask = r.run_anon_subtask("Task Name", func(s): 
    s.log("hello world from anon subtask")
)
await subtask.await_end()
```

Alternatively, you can create an anonymous task first and run it later:

```gdscript
var subtask = r.create_anon_subtask("Task Name", func(s):
    s.log("hello world from anon subtask")
)
# Do other work...
subtask.run_task()
await subtask.await_end()
```

Anonymous tasks support all the same features as registered tasks, including message passing and their own subtask spawning.

**For detailed examples of both registered and anonymous subtasks**, see the "Subtask Management" example in the [Examples directory](../Examples/SampleTasks/subtask_management_sample.gd).

## Project Settings

Customize Task Runner's behavior through Godot's Project Settings.

### Available Settings

**task_runner/default_task_folder**

- **Description**: The default folder where new file tasks are saved when created through the editor plugin
- **Default**: `"res://"`
- **Example**: Set to `"res://tasks/"` to organize all tasks in a dedicated folder
- **Note**: this value is set each time a new on-disk task is created.

**task_runner/tasks**

- **Description**: A list of JSON objects representing each registered task in your project. This setting stores all task configurations including names, types, and execution details
- **Default**: `[]`
- **Important**: It is not recommended to modify this manually. If you do, edit it in an external text editor with the Godot editor closed.

**task_runner/shell_execute/message_prefix**

- **Description**: The prefix string that shell/subprocess tasks use to send structured messages back to Task Runner (used with message passing)
- **Default**: `"TRTASK_MESSAGE_PREFIX"`
- **Example**: Change to `"MSG_PREFIX"` for shorter output logs
- **Note**: This value is shared with all shell types, including PowerShell, Bash, and Command Prompt.

**task_runner/shell_execute/executable**

- **Description**: The shell executable and arguments used to run shell/bash tasks. Can be a single command or an array of command + arguments
- **Default**: `["bash"]`
- **Examples**: 
  - Use Zsh: `["zsh"]`
  - Use sh with explicit command flag: `["sh", "-c"]`
  - Use fish shell: `["fish"]`

### How to Modify Settings

1. Open **Project -> Project Settings**
2. Search for "Task Runner"
3. Adjust the settings as needed
4. Click **Close** to apply changes

Changes to these settings take effect immediately and persist in your project's `project.godot` file.

## Running Tasks from the CLI

### Usage

The Task Runner can be executed from the command line using the `godot` executable. This may be useful for running your tasks as part of a CI/CD pipeline. 

```bash
godot --headless --script --no-header res://addons/TaskRunner/TaskRunnerCLI.gd -- --run-task="Sample - Message Passing"
```

If you are unfamiliar with running Godot from the command line, see the [official command line tutorial](https://docs.godotengine.org/en/latest/tutorials/editor/command_line_tutorial.html#setting-up-the-command-line) for instructions on your platform.

### Supported arguments

* `--run-task, -rt` (required): The name of the task to run.
* `--run-name, -rn` (optional): The name the task run should have.
* `--emit-messages, -m` (optional, default false): True if logs should be output as json, false to output human readable logs.
* `--force-run-in-editor` (optional, default true): True forces the task to run in editor even if it's a new process task. This can prevent some unintended recursive task spawning.

Note that `TaskRunnerCLI.gd` is used internally when "new process gdscript" tasks are run. The flags `--run-name`, `--emit-messages`, and `--force-run-in-editor` mostly exist to be set by the editor when spawning new processes. Typical users likely only need to set the `--run-task` flag.

### Known issues

Some error log spam is expected when running tasks through CLI. See https://github.com/Rushdown-Studios/GodotTaskRunner/issues/8 for details.

---

**Next**: Learn how to [Extend Task Runner](03_extending-task-runner.md) with custom language support and programmatic task registration.
