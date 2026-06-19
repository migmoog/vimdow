local langserver_port = os.getenv "GODOT_LANGSERVER_PORT"
local cmd = vim.lsp.rpc.connect("127.0.0.1", tonumber(langserver_port))

return {
	cmd = cmd,
	filetypes = { "gdscript" },
	root_markers = { "project.godot" }
}
