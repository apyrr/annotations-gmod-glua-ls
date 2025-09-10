--[[
	Shared argument parsing utilities for function call processing.
	
	Provides consistent argument splitting logic for AccessorFunc, NetworkVar, and similar calls.
	Handles string literals, escape sequences, and nested parentheses correctly.
--]]

local ArgParser = {}

---Splits function arguments text into individual argument parts
---@param argsText string Arguments text (e.g., '"Type", 1, "Name"')
---@param options table|nil Options {trackParentheses: boolean}
---@return string[] parts Array of trimmed argument parts
function ArgParser.splitArguments(argsText, options)
	options = options or {}
	local trackParentheses = options.trackParentheses or false
	
	local parts = {}
	local current = ""
	local inString = false
	local stringChar = nil
	local parenDepth = 0

	for i = 1, #argsText do
		local char = argsText:sub(i, i)

		if not inString then
			if char == '"' or char == "'" then
				inString = true
				stringChar = char
				current = current .. char
			elseif trackParentheses and char == "(" then
				parenDepth = parenDepth + 1
				current = current .. char
			elseif trackParentheses and char == ")" then
				parenDepth = parenDepth - 1
				current = current .. char
			elseif char == "," and (not trackParentheses or parenDepth == 0) then
				parts[#parts + 1] = current:match("^%s*(.-)%s*$") -- trim
				current = ""
			else
				current = current .. char
			end
		else
			current = current .. char
			if char == stringChar and argsText:sub(i - 1, i - 1) ~= "\\" then
				inString = false
				stringChar = nil
			end
		end
	end

	if current ~= "" then
		parts[#parts + 1] = current:match("^%s*(.-)%s*$") -- trim
	end

	return parts
end

---Extracts string value from quoted argument
---@param arg string Argument part (e.g., '"Hello"' or "'World'")
---@return string|nil stringValue Extracted string value or nil if not a string
function ArgParser.extractStringValue(arg)
	return arg:match([["([^"]+)"]]) or arg:match([['([^']+)']])
end

---Extracts numeric value from argument
---@param arg string Argument part (e.g., "123" or " 456 ")
---@return number|nil numValue Extracted numeric value or nil if not a number
function ArgParser.extractNumericValue(arg)
	local trimmed = arg:match("^%s*(.-)%s*$")
	return tonumber(trimmed)
end

return ArgParser
