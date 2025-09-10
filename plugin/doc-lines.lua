--[[
	Documentation line formatting helpers for getter/setter/backing-field annotations.

	Provides shared utilities for consistent documentation formatting across processors.
	All functions must reproduce exact strings and ordering as used in the original code.
--]]

local DocLines = {}

---Generates getter method documentation line
---@param name string Method name (e.g., "Health")
---@param selfType string Self type (e.g., "Entity", "ENT")
---@param valueType string Return type (e.g., "number", "string")
---@return string docLine The formatted documentation line
function DocLines.formatGetterLine(name, selfType, valueType)
	return string.format("---@field Get%s fun(self: %s): %s", name, selfType, valueType)
end

---Generates setter method documentation line
---@param name string Method name (e.g., "Health")
---@param selfType string Self type (e.g., "Entity", "ENT")
---@param valueType string Parameter type (e.g., "number", "string")
---@return string docLine The formatted documentation line
function DocLines.formatSetterLine(name, selfType, valueType)
	return string.format("---@field Set%s fun(self: %s, value: %s)", name, selfType, valueType)
end

---Generates backing field documentation line
---@param varKey string Variable key name
---@param valueType string Field type (e.g., "number", "string")
---@return string docLine The formatted documentation line
function DocLines.formatProtectedFieldLine(varKey, valueType)
	return string.format("---@field %s %s", varKey, valueType)
end

---Generates getter/setter pair for AccessorFunc (with specific ordering)
---@param name string Method name
---@param selfType string Self type
---@param valueType string Value type
---@param varKey string|nil Optional backing field variable key
---@return string[] docLines Array of documentation lines in correct order
function DocLines.formatAccessorPair(name, selfType, valueType, varKey)
	local docs = {}

	-- AccessorFunc specific ordering: protected field first (if present), then setter, then getter
	if varKey then
		docs[#docs + 1] = DocLines.formatProtectedFieldLine(varKey, valueType)
	end
	docs[#docs + 1] = DocLines.formatSetterLine(name, selfType, valueType)
	docs[#docs + 1] = DocLines.formatGetterLine(name, selfType, valueType)

	return docs
end

---Generates getter/setter pair for NetworkVar (with specific ordering)
---@param name string Method name
---@param selfType string Self type
---@param valueType string Value type
---@return string[] docLines Array of documentation lines in correct order
function DocLines.formatNetworkVarPair(name, selfType, valueType)
	local docs = {}

	-- NetworkVar specific ordering: setter first, then getter
	docs[#docs + 1] = DocLines.formatSetterLine(name, selfType, valueType)
	docs[#docs + 1] = DocLines.formatGetterLine(name, selfType, valueType)

	return docs
end

---Converts documentation lines array to diff text format
---@param docLines string[] Array of documentation lines
---@return string diffText Formatted text for diff with trailing newline
function DocLines.toDiffText(docLines)
	return table.concat(docLines, "\n") .. "\n"
end

return DocLines
