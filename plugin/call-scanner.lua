--[[
  Generic function call scanning utility to robustly extract argument text from function-like patterns.

  This exists because patterns are annoying
]]

local CallScanner = {}

---Scans forward from the given index (which should point to the character just after the opening parenthesis)
---and returns the index of the matching closing parenthesis accounting for nesting and strings.
---@param text string
---@param startIndex integer  -- index of first character after the "(" that began the argument list
---@return integer|nil closeIndex
local function findMatchingParen(text, startIndex)
	local depth = 1
	local inString = false
	local stringChar = nil
	local i = startIndex
	while i <= #text do
		local ch = text:sub(i, i)
		if inString then
			if ch == stringChar and text:sub(i - 1, i - 1) ~= '\\' then
				inString = false
				stringChar = nil
			end
		else
			if ch == '"' or ch == "'" then
				inString = true
				stringChar = ch
			elseif ch == '(' then
				depth = depth + 1
			elseif ch == ')' then
				depth = depth - 1
				if depth == 0 then
					return i
				end
			end
		end
		i = i + 1
	end
	return nil
end

---Finds calls given a prefix pattern (which should include optional whitespace and the opening parenthesis).
---The pattern must end with '%(' so we know where the arguments start.
---@param text string
---@param pattern string
---@return table[] calls
function CallScanner.findCalls(text, pattern)
	-- Basic validation: ensure pattern ends with '%(' to anchor the scan start.
	if not pattern:match("%%%($") then
		-- Misconfigured pattern; return empty to avoid runtime errors.
		return {}
	end
	local calls = {}
	local searchStart = 1
	while true do
		local s, e = text:find(pattern, searchStart)
		if not s then break end
		-- e points to the "(" due to pattern ending with '%('
		local argsStart = e + 1
		local closeIndex = findMatchingParen(text, argsStart)
		if not closeIndex then
			-- Unbalanced; abort further scanning to avoid infinite loop
			break
		end
		local argsText = text:sub(argsStart, closeIndex - 1)
		calls[#calls + 1] = {
			argsText = argsText,
			position = s,
			closeIndex = closeIndex,
		}
		searchStart = closeIndex + 1
	end
	return calls
end

return CallScanner
