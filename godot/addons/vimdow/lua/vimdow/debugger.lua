local M = {
	breakpoints = {}
}

local BREAKPOINTS_GROUP = "vimdow_breakpoints"

function M.set_breakpoint (buf, line, val, external)
	if not M.breakpoints[buf] then
		M.breakpoints[buf] = {}
	end

	if val then
		if M.breakpoints[buf][line] then
			return
		end

		M.breakpoints[buf][line] = vim.fn.sign_place(0, BREAKPOINTS_GROUP, "GodotBreakpoint", buf, {
			lnum = line,
			priority = 43,
		})
	else
		if not M.breakpoints[buf][line] then
			return
		end

		vim.fn.sign_unplace(BREAKPOINTS_GROUP, {
			buffer = buf,
			id = M.breakpoints[buf][line],
		})
		M.breakpoints[buf][line] = nil
	end

	if not external then
		local result = vim.fn.rpcrequest(1, "vimdow_set_breakpoint", buf, line, val)
		if result ~= vim.NIL then
			vim.print(result)
		end
	end
end

function M.clear_breakpoints (buf)
	if buf then
		vim.fn.sign_unplace(BREAKPOINTS_GROUP, {
			buffer = buf,
		})
		M.breakpoints[buf] = {}
	else
		vim.fn.sign_unplace(BREAKPOINTS_GROUP)
		M.breakpoints = {}
	end
end

function M.get_breakpoint (buf, line)
	local bps = M.breakpoints[buf]
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

function M.toggle_breakpoint (buf, line)
	M.set_breakpoint(buf, line, not M.get_breakpoint(buf, line))
end

return M
