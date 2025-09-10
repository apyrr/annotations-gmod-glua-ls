--[[
	Handles all Derma/VGUI panel registration processing.
--]]

local DermaProcessor = {}
local CallScanner = require("plugin.call-scanner")

---Checks if a class documentation already exists anywhere in the text
---@param text string
---@param className string
---@return boolean
local function hasExistingClassDoc(text, className)
	if not className or className == '' then return false end
	local pattern = "---@class%s+" .. className .. "[%s:]"
	return text:find(pattern) ~= nil
end

---Find the start index of the line containing pos
---@param text string
---@param pos integer
---@return integer lineStart
local function lineStartAt(text, pos)
	if pos <= 1 then return 1 end
	local before = text:sub(1, pos - 1)
	local last = 1
	for s in before:gmatch("\n()") do
		last = tonumber(s) or last
	end
	return last
end

---Expands insertion range upward to consume any blank-only lines immediately above the target line
---@param text string
---@param lineStart integer  -- start index of the target assignment line
---@return integer insertStart
local function expandUpThroughBlankLines(text, lineStart)
	local insertStart = lineStart
	local i = lineStart - 1
	while i > 0 do
		-- find start of previous line
		local prevStart = 1
		local prefix = text:sub(1, i - 1)
		for s in prefix:gmatch("\n()") do
			prevStart = tonumber(s) or prevStart
		end
		local prevLine = text:sub(prevStart, i - 1)
		if prevLine:match("^%s*$") then
			insertStart = prevStart
			i = prevStart - 1
		else
			break
		end
	end
	return insertStart
end

---Processes Derma panel registrations in text and generates documentation diffs
---@param text string File content
---@param config table Configuration with patterns
---@return table[] diffs Array of documentation diffs
function DermaProcessor.processDermaRegistrations(text, config)
	local diffs = {}
	local patterns = config.patterns or {}

	-- Process vgui.Register calls
	local vguiDiffs = DermaProcessor.processVguiRegistrations(text, patterns)
	for _, diff in ipairs(vguiDiffs) do
		diffs[#diffs + 1] = diff
	end

	-- Process derma.DefineControl calls
	local dermaDiffs = DermaProcessor.processDermaDefineControl(text, patterns)
	for _, diff in ipairs(dermaDiffs) do
		diffs[#diffs + 1] = diff
	end

	return diffs
end

---Find the nearest prior assignment for a given table name before a position
---@param text string
---@param tableName string
---@param beforePos integer  -- insertion should happen before this position
---@return integer|nil pos   -- start index of the assignment keyword (e.g., the 'l' in 'local')
local function findNearestPriorAssignment(text, tableName, beforePos)
	if not tableName or not beforePos then return nil end
	-- Escape any magic chars in the name
	local escaped = tableName:gsub("(%p)", "%%%1")

	-- Prefer a local assignment:  %f[%a]local%s+<name>%s*=
	local localPattern = "%f[%a]local%s+" .. escaped .. "%s*="

	local lastLocal
	local searchStart = 1
	while true do
		local s, e = text:find(localPattern, searchStart)
		if not s or s >= beforePos then break end
		lastLocal = s
		searchStart = e + 1
	end

	-- Fallback: any assignment at line start (non-local). Anchor at line start to avoid mid-expression matches.
	-- Pattern: ^%s*<name>%s*=
	local lastGlobal
	searchStart = 1
	while true do
		local s, e = text:find("\n()%s*" .. escaped .. "%s*=", searchStart)
		-- s returned by () is the index right after the newline; adjust to point to beginning of the line
		if not s then break end
		-- Convert s (start-of-capture) to full position in original string
		local lineStart = s
		if lineStart < beforePos then
			lastGlobal = lineStart
		else
			break
		end
		searchStart = e + 1
	end
	-- Also check the very beginning of the file (first line) separately
	do
		local s = text:find("^%s*" .. escaped .. "%s*=")
		if s and s < beforePos then
			lastGlobal = s
		end
	end

	-- Choose the nearest assignment before the call, regardless of local/global
	local best = nil
	if lastLocal and lastLocal < beforePos then best = lastLocal end
	if lastGlobal and lastGlobal < beforePos then
		if not best or lastGlobal > best then
			best = lastGlobal
		end
	end
	return best
end

---Processes vgui.Register calls in text
---@param text string File content
---@param patterns table Pattern configurations
---@return table[] diffs Array of documentation diffs
function DermaProcessor.processVguiRegistrations(text, patterns)
	local diffs = {}
	local vguiPattern = patterns.vguiRegister

	-- Find all vgui.Register calls
	local registrations = DermaProcessor.findVguiRegistrations(text, vguiPattern)

	for _, registration in ipairs(registrations) do
		local diff = DermaProcessor.createVguiDocumentation(registration, text)
		if diff then
			diffs[#diffs + 1] = diff
		end
	end

	return diffs
end

---Processes derma.DefineControl calls in text
---@param text string File content
---@param patterns table Pattern configurations
---@return table[] diffs Array of documentation diffs
function DermaProcessor.processDermaDefineControl(text, patterns)
	local diffs = {}
	local dermaPattern = patterns.dermaDefineControl

	-- Find all derma.DefineControl calls
	local definitions = DermaProcessor.findDermaDefinitions(text, dermaPattern)

	for _, definition in ipairs(definitions) do
		local diff = DermaProcessor.createDermaDocumentation(definition, text)
		if diff then
			diffs[#diffs + 1] = diff
		end
	end

	return diffs
end

---Finds vgui.Register calls in text
---@param text string File content
---@param pattern string Search pattern
---@return table[] registrations Array of registration info
function DermaProcessor.findVguiRegistrations(text, pattern)
	local registrations = {}
	local raw = CallScanner.findCalls(text, pattern)
	for _, c in ipairs(raw) do
		local args = DermaProcessor.parseVguiArgs(c.argsText)
		if args and args.name and args.table then
			registrations[#registrations + 1] = {
				name = args.name,
				table = args.table,
				base = args.base,
				position = c
					.position
			}
		end
	end
	return registrations
end

---Finds derma.DefineControl calls in text
---@param text string File content
---@param pattern string Search pattern
---@return table[] definitions Array of definition info
function DermaProcessor.findDermaDefinitions(text, pattern)
	local definitions = {}
	local raw = CallScanner.findCalls(text, pattern)
	for _, c in ipairs(raw) do
		local args = DermaProcessor.parseDermaArgs(c.argsText)
		if args and args.name and args.table then
			definitions[#definitions + 1] = {
				name = args.name,
				description = args.description,
				table = args.table,
				base =
					args.base,
				position = c.position
			}
		end
	end
	return definitions
end

---Parses vgui.Register arguments
---@param argsText string Arguments text
---@return table|nil args Parsed arguments
function DermaProcessor.parseVguiArgs(argsText)
	local name = argsText:match([["([^"]+)"]]) or argsText:match([['([^']+)']])
	if not name then return nil end

	local tableRef = argsText:match(",%s*([%a_][%w_%.]*)")
	if not tableRef then return nil end

	local base = argsText:match([[,%s*"([^"]+)"]]) or argsText:match([[,%s*'([^']+)']])

	return {
		name = name,
		table = tableRef,
		base = base
	}
end

---Parses derma.DefineControl arguments
---@param argsText string Arguments text
---@return table|nil args Parsed arguments
function DermaProcessor.parseDermaArgs(argsText)
	local name = argsText:match([["([^"]+)"]]) or argsText:match([['([^']+)']])
	if not name then return nil end

	local remaining = argsText:match([[^[^,]*,%s*"[^"]*",%s*(.*)$]]) or
		argsText:match([[^[^,]*,%s*'[^']*',%s*(.*)$]])
	if not remaining then return nil end

	local tableRef = remaining:match("([%a_][%w_%.]*)")
	if not tableRef then return nil end

	local base = remaining:match([[,%s*"([^"]+)"]]) or remaining:match([[,%s*'([^']+)']])

	return {
		name = name,
		table = tableRef,
		base = base
	}
end

---Creates documentation diff for vgui registration
---@param registration table Registration info
---@param text string Full file content
---@return table|nil diff Documentation diff
function DermaProcessor.createVguiDocumentation(registration, text)
	-- Skip if a class doc for this panel already exists in the file
	if hasExistingClassDoc(text, registration.name) then
		return nil
	end
	-- Find the nearest table definition location before the registration call
	local tablePos = findNearestPriorAssignment(text, registration.table, registration.position)
	if not tablePos then return nil end

	-- Generate class documentation
	local className = registration.name
	local baseClass = registration.base or "Panel"

	local docText = string.format("---@class %s : %s\n", className, baseClass)

	-- Ensure doc is immediately above the table by replacing any blank-only lines above it
	local lineStart = lineStartAt(text, tablePos)
	local insertStart = expandUpThroughBlankLines(text, lineStart)
	return {
		start = insertStart,
		finish = lineStart - 1,
		text = docText
	}
end

---Creates documentation diff for derma definition
---@param definition table Definition info
---@param text string Full file content
---@return table|nil diff Documentation diff
function DermaProcessor.createDermaDocumentation(definition, text)
	-- Skip if a class doc for this panel already exists in the file
	if hasExistingClassDoc(text, definition.name) then
		return nil
	end
	-- Find the nearest table definition location before the definition call
	local tablePos = findNearestPriorAssignment(text, definition.table, definition.position)
	if not tablePos then return nil end

	-- Generate class documentation
	local className = definition.name
	local baseClass = definition.base or "Panel"

	local docText = string.format("---@class %s : %s\n", className, baseClass)

	-- Ensure doc is immediately above the table by replacing any blank-only lines above it
	local lineStart = lineStartAt(text, tablePos)
	local insertStart = expandUpThroughBlankLines(text, lineStart)
	return {
		start = insertStart,
		finish = lineStart - 1,
		text = docText
	}
end

---Checks if text contains Derma registrations
---@param text string File content
---@param patterns table Pattern configurations
---@return boolean hasRegistrations
function DermaProcessor.hasDermaRegistrations(text, patterns)
	local vguiPattern = patterns.vguiRegister
	local dermaPattern = patterns.dermaDefineControl

	return text:find(vguiPattern) ~= nil or text:find(dermaPattern) ~= nil
end

return DermaProcessor
