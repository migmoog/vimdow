

_G.Vimdow = {
	-- breakpoints managed by the godot editor
	_gd_breakpoints = {},
}
local env = os.getenv

function Vimdow.toggle_breakpoint (buf, line)
	local bps = Vimdow._gd_breakpoints[buf]
	if bps then
		local bpi
		for i, v in ipairs(bps) do
			if v == line then
				bpi = i
				break
			end
		end

		if bpi then
			table.remove(bps, bpi)
			vim.fn.sign_unplace("vimdow_breakpoints", {
				buffer = buf,
			})
		else
			table.insert(bps, bpi)
			vim.fn.sign_place(0, "vimdow_breakpoints", "GodotBreakpoint", buf, {
				lnum = line,
			})
		end

		local result = vim.fn.rpcrequest(1, "vimdow_toggle_breakpoint", buf, line)
		-- result is nil on success
		if result then
			vim.print(result)
		end
	else
		bps = {}
		table.insert(bps, line)
		Vimdow._gd_breakpoints[buf] = bps
	end
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
		local tb = keybinds.toggle_breakpoint or "gb"
		vim.keymap.set("n", tb, function ()
			local buf = vim.bo[vim.api.nvim_get_current_buf()]

			if buf.filetype ~= "gdscript" then
				return
			end

			local _, linenum = vim.api.nvim_win_get_cursor(0)
			Vimdow.toggle_breakpoint(buf, linenum)
		end, {
			desc = "toggle godot breakpoint on cursor line",
		})
	end
end

-- plugin initilization
local user_config = dofile("addons/vimdow/lua/vimdow/config.lua")
Vimdow.setup(user_config)
