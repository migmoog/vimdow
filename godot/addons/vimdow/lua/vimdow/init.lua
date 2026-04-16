_G.Vimdow = {
	-- breakpoints managed by the godot editor
	breakpoints = {},
}
local env = os.getenv

local BREAKPOINTS_GROUP = "vimdow_breakpoints"

function Vimdow.clear_breakpoints (buf)
	vim.fn.sign_unplace(BREAKPOINTS_GROUP)
	Vimdow.breakpoints[buf] = {}
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

	local result = vim.fn.rpcrequest(1, "vimdow_set_breakpoint", buf, line)
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

	vim.fn.sign_define("GodotBreakpoint", {
		text = "",
	})

	local keybinds = opts.keybinds
	if keybinds then
		local tb = keybinds.toggle_breakpoint or "<leader>gb"
		vim.keymap.set("n", tb, function ()
			local bufnr = vim.api.nvim_get_current_buf()
			local buf = vim.bo[bufnr]

			if buf.filetype ~= "gdscript" then
				return
			end

			local linenum = vim.api.nvim_win_get_cursor(0)[1]
			Vimdow.toggle_breakpoint(vim.fn.bufname(), linenum)
		end, {
			desc = "toggle godot breakpoint on cursor line",
		})

		local cb = keybinds.clear_breakpoints or "<leader>cb"
		vim.keymap.set("n", cb, function ()
			local bufnr = vim.api.nvim_get_current_buf()
			local buf = vim.bo[bufnr]

			if buf.filetype ~= "gdscript" then
				return
			end
			Vimdow.clear_breakpoints(vim.fn.bufname())
		end, {
			desc = "clear all godot breakpoints in this buffer",
		})
	end
end

-- plugin initilization
local user_config = dofile "addons/vimdow/lua/vimdow/config.lua"
Vimdow.setup(user_config)
