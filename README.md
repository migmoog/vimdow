<h1 align="center"> Vimdow </h1>

<h1 align="center">
    <img src="img/vimdow_logo.png" alt="Vimdow Logo" width="320" height="320">
</h1>
<div align="center">
    It's two things at once!
    <ul>
        <li> A <a href="https://neovim.io">Neovim</a> client based on godot </li>
        <li> A <a href="https://godotengine.org">Godot</a> editor plugin that lets you use neovim </li>
    </ul>
</div>

<p align="center">
    <img alt="GitHub Downloads (all assets, all releases)" src="https://img.shields.io/github/downloads/migmoog/vimdow/total">
    <img alt="GitHub Release" src="https://img.shields.io/github/v/release/migmoog/vimdow">
</p>

## About

Tired of godot's in-house script editor? **Vimdow** can let you use the comfort of your own neovim config 
to edit text for any file you want!

Vimdow can be installed like a regular plugin off of the asset store, or
it can be downloaded as a standalone neovim client for your system.

### What's neovim?

If you don't know, [watch this](https://www.youtube.com/watch?v=c4OyfL5o7DU).

In short it's a keyboard centric text editor that can enable high productivity should you choose to master it.
It also follows the philosophy of "Configuration as Code", meaning you can create a highly personalized environment suited 
to your needs.

Vimdow aims to provide this accessibility to Godot developers!

### Project Goals / Features

- A customizable neovim frontend, configurable via [ themes ](https://docs.godotengine.org/en/stable/tutorials/ui/gui_using_theme_editor.html)
- Portability, vimdow can work wherever Godot can
- A neovim experience that is seamless between both the Godot editor and using Neovim on your own system

## Configuration

**Requirements**: Neovim 0.11 or later.

Vimdow only needs to know where Neovim's binary is located on your system to get working. By default both modes assume 
that your on linux and set the path to `/usr/bin/nvim`

### Plugin mode

#### Path to neovim

To tell the plugin where Neovim is, check your [ Project Settings ](https://docs.godotengine.org/en/stable/tutorials/editor/project_settings.html) and paste the path to the binary in `"vimdow/path_to_nvim"`

#### Theme

Edit `addons/vimdow/vimdow_theme.tres` in the editor to do things like change fonts and default font size.

#### Shortcuts

Keyboard shortcuts (such as font size) are located under `Editor Settings > Shortcuts > Vimdow`.

#### Lua plugin

Vimdow is also a neovim plugin. The code for it is located in `addons/vimdow/lua`. In it is the `init.lua` script that is used on neovim startup with the `-S` flag. The other file is the configurations, the defaults of which are:
```lua
{
	-- Default keybindings for vimdow actions
	keybinds = {
		toggle_breakpoint = "<leader>gb",
		clear_breakpoints = "<leader>cb"
	},

	-- default color themes
	colors = {
		-- color when a brekpoint gutter is hovered with a mouse
		breakpoint_hover = "#ffabb2",

		-- color when a breakpoint is set
		set_breakpoint = "#ff0016"
	},
}
```
