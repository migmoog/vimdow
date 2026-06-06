_G.Vimdow = {}

function Vimdow.drop_text (text, col, row)
	for _, id in pairs(vim.api.nvim_list_wins()) do
		local winwidth = vim.api.nvim_win_get_width(id)
		local winheight = vim.api.nvim_win_get_height(id)
		local winpos = vim.api.nvim_win_get_position(id)
		local winrow, wincol = winpos[1], winpos[2]

		if wincol <= col and col < wincol + winwidth and winrow <= row and row < winrow + winheight then
			local oldpos = vim.api.nvim_win_get_cursor(id)
			-- moves the cursor to the clicked spot
			vim.api.nvim_input_mouse("left", "press", "", 0, row, col)
			vim.schedule(function()
				vim.api.nvim_paste(text, false, -1)
				vim.api.nvim_win_set_cursor(id, oldpos)
			end)
			return
		end
	end
end

function Vimdow.setup (opts)
	local colors = opts.colors or {}
	Vimdow.hover_breakpoint_hl = "VimdowHoverBreakpoint"
	vim.api.nvim_set_hl(0, Vimdow.hover_breakpoint_hl, { fg = colors.breakpoint_hover or "#ffabb2" })

	Vimdow.set_breakpoint_hl = "VimdowSetBreakpoint"
	vim.api.nvim_set_hl(0, Vimdow.set_breakpoint_hl, { fg = colors.set_breakpoint or "#ff0016" })

	vim.fn.sign_define("GodotBreakpoint", {
		text = "",
		texthl = Vimdow.set_breakpoint_hl,
	})

	vim.fn.sign_define("GodotBreakpointHover", {
		text = "",
		texthl = Vimdow.hover_breakpoint_hl,
	})

	local debugger = require "vimdow.debugger"
	Vimdow.get_breakpoint = debugger.get_breakpoint
	Vimdow.set_breakpoint = debugger.set_breakpoint
	Vimdow.toggle_breakpoint = debugger.toggle_breakpoint
	Vimdow.clear_breakpoints = debugger.clear_breakpoints

	-- breakpoint toggling
	local keybinds = opts.keybinds or {}
	local tb = keybinds.toggle_breakpoint or "<leader>gb"
	vim.api.nvim_create_user_command("VimdowToggleBreakpoint", function (o)
		if vim.bo.filetype ~= "gdscript" then
			return
		end

		local linenum = tonumber(o.fargs[1]) or vim.api.nvim_win_get_cursor(0)[1]
		Vimdow.toggle_breakpoint(vim.fn.bufname(), linenum)
	end, {
		nargs = "?",
	})
	vim.keymap.set("n", tb, ":VimdowToggleBreakpoint<CR>", {
		desc = "toggle godot breakpoint on cursor line",
	})

	-- breakpoint clearing
	local cb = keybinds.clear_breakpoints or "<leader>cb"
	vim.api.nvim_create_user_command("VimdowClearBreakpoints", function (o)
		if vim.bo.filetype ~= "gdscript" then
			return
		end
		local path = o.fargs[1] or vim.fn.bufname()
		Vimdow.clear_breakpoints(path)

		local result = vim.fn.rpcrequest(1, "vimdow_clear_breakpoints", path)
		if result ~= vim.NIL then
			vim.print(result)
		end
	end, {
		nargs = "?",
	})
	vim.keymap.set("n", cb, ":VimdowClearBreakpoints<CR>", {
		desc = "clear all godot breakpoints in this buffer",
	})

	-- setting breakpoints with the mouse
	Vimdow.bpmouse = {
		line = -1,
		signid = 1,
	}
	-- breakpoint hover
	vim.keymap.set("n", "<MouseMove>", function ()
		local pos = vim.fn.getmousepos()
		if vim.bo.filetype ~= "gdscript" or pos.line == 0 then
			return
		end

		local b = Vimdow.bpmouse
		local function remove_hover ()
			if b.line > -1 then
				vim.fn.sign_unplace "hover"
			end
		end
		if pos.wincol > 5 then
			remove_hover()
			b.line = -1
		elseif pos.line ~= b.line then
			remove_hover()

			b.line = pos.line
			vim.fn.sign_place(b.signid, "hover", "GodotBreakpointHover", vim.fn.bufname(), {
				lnum = b.line,
				priority = 42,
			})
		end
	end, {})

	-- breakpoint set with mouse
	vim.keymap.set("n", "<LeftRelease>", function ()
		local pos = vim.fn.getmousepos()
		if vim.bo.filetype ~= "gdscript" or pos.line == 0 or pos.wincol > 5 then
			return
		end

		Vimdow.toggle_breakpoint(vim.fn.bufname(), pos.line)
	end)

	-- releasing focus from vimdow back to the editor
	local rf = keybinds.release_focus or "<C-Esc>"
	vim.keymap.set("n", rf, function ()
		local result = vim.fn.rpcrequest(1, "release_focus")
		if result ~= vim.NIL then
			vim.print("Vimdow exited focus: " .. tostring(result))
		end
	end)

	-- editor interface integration
	Vimdow.ei = require "vimdow.editor"
end

return Vimdow
