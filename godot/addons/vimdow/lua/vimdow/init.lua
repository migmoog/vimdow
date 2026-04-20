_G.Vimdow = {
	-- breakpoints managed by the godot editor
	breakpoints = {},
}
local env = os.getenv

local BREAKPOINTS_GROUP = "vimdow_breakpoints"

function Vimdow.clear_breakpoints (buf)
	if buf then
		vim.fn.sign_unplace(BREAKPOINTS_GROUP, {
			buffer = buf,
		})
		Vimdow.breakpoints[buf] = {}
	else
		vim.fn.sign_unplace(BREAKPOINTS_GROUP)
		Vimdow.breakpoints = {}
	end
end

function Vimdow.set_breakpoint (buf, line, val)
	if not Vimdow.breakpoints[buf] then
		Vimdow.breakpoints[buf] = {}
	end

	if val then
		if Vimdow.breakpoints[buf][line] then
			return
		end

		Vimdow.breakpoints[buf][line] = vim.fn.sign_place(0, BREAKPOINTS_GROUP, "GodotBreakpoint", buf, {
			lnum = line,
			priority = 43,
		})
	else
		if not Vimdow.breakpoints[buf][line] then
			return
		end

		vim.fn.sign_unplace(BREAKPOINTS_GROUP, {
			buffer = buf,
			id = Vimdow.breakpoints[buf][line],
		})
		Vimdow.breakpoints[buf][line] = nil
	end

	local result = vim.fn.rpcrequest(1, "vimdow_set_breakpoint", buf, line, val)
	if result ~= vim.NIL then
		vim.print(result)
	end
end

function Vimdow.get_breakpoint (buf, line)
	local bps = Vimdow.breakpoints[buf]
	if not bps then
		return false
	elseif bps then
		for k, _ in pairs(bps) do
			if k == line then
				return true
			end
		end
		return false
	end
end

function Vimdow.toggle_breakpoint (buf, line)
	Vimdow.set_breakpoint(buf, line, not Vimdow.get_breakpoint(buf, line))
end

function Vimdow.setup (opts)
	local root_dir = opts.root_dir or vim.fs.root(0, { "project.godot" })
	if not root_dir then
		return
	end
	local v = Vimdow
	v.root_dir = root_dir

	-- Automatically connect to the language server
	local langserver_port = env "GODOT_LANGSERVER_PORT"
	vim.lsp.config("gdscript", {
		cmd = vim.lsp.rpc.connect("127.0.0.1", tonumber(langserver_port)),
	})
	vim.lsp.enable "gdscript"

	local gd_version = opts.gd_version or env "GODOT_VERSION"

	Vimdow.hover_breakpoint_hl = "VimdowHoverBreakpoint"
	vim.api.nvim_set_hl(0, Vimdow.hover_breakpoint_hl, { fg = opts.breakpoint_hover_fg or "#ffabb2" })

	Vimdow.set_breakpoint_hl = "VimdowSetBreakpoint"
	vim.api.nvim_set_hl(0, Vimdow.set_breakpoint_hl, { fg = opts.breakpoint_hover_bg or "#ff0016" })

	vim.fn.sign_define("GodotBreakpoint", {
		text = "",
		texthl = Vimdow.set_breakpoint_hl,
	})

	vim.fn.sign_define("GodotBreakpointHover", {
		text = "",
		texthl = Vimdow.hover_breakpoint_hl,
	})

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
		local function remove_hover()
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
end

-- plugin initilization
local user_config = dofile "addons/vimdow/lua/vimdow/config.lua"
Vimdow.setup(user_config)
