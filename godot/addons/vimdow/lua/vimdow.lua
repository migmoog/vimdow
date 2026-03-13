_G.Vimdow = {
  is_godot_project = false
}

local root_dir = vim.fs.root(0, {"project.godot"})
Vimdow.is_godot_project = root_dir ~= nil

if Vimdow.is_godot_project then
  vim.api.nvim_create_autocmd("FileType", {
    pattern = { "gdscript", "gd" },
    callback = function()
      local cmd = vim.lsp.rpc.connect('127.0.0.1', 6005)
      vim.lsp.start {
        name = "godot",
        cmd = cmd,
        root_dir = root_dir,
        filetypes = { "gdscript", "gd" },
      }
    end
  })
end
