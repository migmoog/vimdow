-- hl_decoration_test.lua
-- Tests every hl_attr decoration style for a custom GUI renderer.
-- Run with: nvim --clean -u hl_decoration_test.lua

local api = vim.api

local styles = {
  -- ── single decorations ───────────────────────────────────────────────────
  { name = "D_Underline",      attrs = { underline      = true }, sp = "#57C7FF", label = "underline" },
  { name = "D_Underdouble",    attrs = { underdouble    = true }, sp = "#FF79C6", label = "underdouble" },
  { name = "D_Underdotted",    attrs = { underdotted    = true }, sp = "#5AF78E", label = "underdotted" },
  { name = "D_Underdashed",    attrs = { underdashed    = true }, sp = "#FF9F43", label = "underdashed" },
  { name = "D_Undercurl",      attrs = { undercurl      = true }, sp = "#FF5555", label = "undercurl" },
  { name = "D_Strikethrough",  attrs = { strikethrough  = true }, sp = "#F1FA8C", label = "strikethrough" },
  { name = "D_Overline",       attrs = { overline       = true }, sp = "#BD93F9", label = "overline" },

  -- ── sp colour variations (undercurl as the carrier) ─────────────────────
  { name = "D_Curl_Red",       attrs = { undercurl = true }, sp = "#FF5555", label = "undercurl  sp=red" },
  { name = "D_Curl_Blue",      attrs = { undercurl = true }, sp = "#57C7FF", label = "undercurl  sp=blue" },
  { name = "D_Curl_NoSp",      attrs = { undercurl = true }, sp = nil,       label = "undercurl  no sp  (fallback to fg)" },

  -- ── decoration + bold (baseline shift test) ─────────────────────────────
  { name = "D_Under_Bold",     attrs = { underline     = true, bold = true }, sp = "#57C7FF", label = "underline  + bold" },
  { name = "D_Curl_Bold",      attrs = { undercurl     = true, bold = true }, sp = "#FF5555", label = "undercurl  + bold" },
  { name = "D_Double_Bold",    attrs = { underdouble   = true, bold = true }, sp = "#FF79C6", label = "underdouble + bold" },

  -- ── blend ────────────────────────────────────────────────────────────────
  { name = "D_Blend25",        attrs = { blend = 25  }, sp = nil, label = "blend=25  (nearly opaque)" },
  { name = "D_Blend50",        attrs = { blend = 50  }, sp = nil, label = "blend=50  (half transparent)" },
  { name = "D_Blend75",        attrs = { blend = 75  }, sp = nil, label = "blend=75  (mostly transparent)" },

  -- ── url ──────────────────────────────────────────────────────────────────
  { name = "D_Url",            attrs = { underline = true, url = "https://example.com" }, sp = "#57C7FF", label = "url  (underline + url attr)" },

  -- ── stacked decorations ──────────────────────────────────────────────────
  { name = "D_Under_Over",     attrs = { underline     = true, overline      = true }, sp = "#57C7FF", label = "underline  + overline" },
  { name = "D_Curl_Strike",    attrs = { undercurl     = true, strikethrough = true }, sp = "#FF5555", label = "undercurl  + strikethrough" },
  { name = "D_Double_Strike",  attrs = { underdouble   = true, strikethrough = true }, sp = "#FF79C6", label = "underdouble + strikethrough" },
  { name = "D_Dotted_Over",    attrs = { underdotted   = true, overline      = true }, sp = "#5AF78E", label = "underdotted + overline" },
  { name = "D_Dashed_Strike",  attrs = { underdashed   = true, strikethrough = true }, sp = "#FF9F43", label = "underdashed + strikethrough" },
}

local TEXT = "The quick brown fox jumps over the lazy dog"

for _, s in ipairs(styles) do
  local parts = { "highlight", s.name, "guifg=#F8F8F2" }
  if s.sp then table.insert(parts, "guisp=" .. s.sp) end
  local gui = {}
  for k, v in pairs(s.attrs) do
    if v == true then table.insert(gui, k) end
  end
  if s.attrs.blend then table.insert(parts, "blend=" .. s.attrs.blend) end
  if #gui > 0 then table.insert(parts, "gui=" .. table.concat(gui, ",")) end
  vim.cmd(table.concat(parts, " "))
end

-- ─── scratch buffer ──────────────────────────────────────────────────────────

local buf = api.nvim_create_buf(false, true)
api.nvim_buf_set_name(buf, "hl_decoration_test")
api.nvim_set_option_value("buftype",    "nofile", { buf = buf })
api.nvim_set_option_value("bufhidden",  "wipe",   { buf = buf })
api.nvim_set_option_value("modifiable", true,     { buf = buf })

local lines = {
  "  hl_attr decoration style test",
  "  ════════════════════════════════════════════════════════════════════════",
  "",
  "  ── single styles ───────────────────────────────────────────────────────",
  "",
}
local hl_ranges = {}

local sections = {
  { heading = "── sp colour / fallback ────────────────────────────────────────────────", from = "D_Curl_Red" },
  { heading = "── + bold (baseline shift) ─────────────────────────────────────────────", from = "D_Under_Bold" },
  { heading = "── blend ───────────────────────────────────────────────────────────────", from = "D_Blend25" },
  { heading = "── stacked decorations ─────────────────────────────────────────────────", from = "D_Under_Over" },
}

local section_map = {}
for _, sec in ipairs(sections) do
  section_map[sec.from] = sec.heading
end

for _, s in ipairs(styles) do
  if section_map[s.name] then
    table.insert(lines, "")
    table.insert(lines, "  " .. section_map[s.name])
    table.insert(lines, "")
  end
  local lnum = #lines
  table.insert(lines, string.format("  %-30s  %s", s.label, TEXT))
  table.insert(hl_ranges, { lnum = lnum, group = s.name })
end

table.insert(lines, "")

api.nvim_buf_set_lines(buf, 0, -1, false, lines)

for _, r in ipairs(hl_ranges) do
  local line = lines[r.lnum + 1]
  local text_start = line:find("The") - 1
  api.nvim_buf_add_highlight(buf, -1, r.group, r.lnum, text_start, -1)
end

api.nvim_set_option_value("modifiable", false, { buf = buf })
api.nvim_set_current_buf(buf)
