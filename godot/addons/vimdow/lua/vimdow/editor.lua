local mt = {}

-- allows users to call the EditorInterface methods via the lua plugin
mt.__index = function (_tb, method_name)
	return function (...)
		local response = vim.fn.rpcrequest(1, "EditorInterface:" .. method_name, ...)

		return response.return_value
	end
end

local M = {}

M = setmetatable(M, mt)

return M
