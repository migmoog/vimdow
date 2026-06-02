-- this adds the lua plugin to your neovim session
vim.opt.rtp:prepend(vim.fs.joinpath(vim.fn.getcwd(), "addons/vimdow"))

-- this initializes the plugin for you
require("vimdow").setup {
	-- Default keybindings for vimdow actions
	keybinds = {
		-- toggle_breakpoint = "<leader>gb",
		-- clear_breakpoints = "<leader>cb",
		-- release_focus ="<C-Esc>"
	},

	-- default color themes
	colors = {
		-- color when a brekpoint gutter is hovered with a mouse
		-- breakpoint_hover = "#ffabb2",

		-- color when a breakpoint is set
		-- set_breakpoint = "#ff0016"
	},
}

vim.lsp.enable "gdscript"
