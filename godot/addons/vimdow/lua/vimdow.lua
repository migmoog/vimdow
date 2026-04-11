local cfg = vim.lsp.config["gdscript"]
local markers = (cfg and cfg.root_markers) or { "project.godot" }

_G.Vimdow = {
	is_godot_project = vim.fs.root(0, markers) ~= nil,
}

-- if set, overrides nvim-lspconfig's default port (6005)
local langserver_port = os.getenv "GODOT_LANGSERVER_PORT"

if langserver_port then
	vim.lsp.config("gdscript", {
		cmd = vim.lsp.rpc.connect("127.0.0.1", tonumber(langserver_port)),
	})
end

-- NOTE: this will only activate based on filetypes and root_markers
vim.lsp.enable "gdscript"
