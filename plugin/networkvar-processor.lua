--[[
	Handles NetworkVar and NetworkVarElement call processing and generates getter/setter documentation.

	Processes NetworkVar(type, slot, name) and NetworkVarElement(type, slot, element, name) calls and generates:
	- Setter method documentation (Set<Name>)
	- Getter method documentation (Get<Name>)

	Supports data type resolution from config.dtTypes mapping (DT_* constants to Lua types).
--]]

local DocLines = require("plugin.doc-lines")
local ArgParser = require("plugin.arg-parser")
local CallScanner = require("plugin.call-scanner")
local NetworkVarProcessor = {}

---Processes NetworkVar calls in text and generates documentation diffs
---@param text string File content
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@return table[] diffs Array of documentation diffs
function NetworkVarProcessor.processNetworkVars(text, global, class, config)
	local diffs = {}

	-- Process NetworkVar calls
	local networkVarDiffs = NetworkVarProcessor.processNetworkVarCalls(text, global, class, config)
	for _, diff in ipairs(networkVarDiffs) do
		diffs[#diffs + 1] = diff
	end

	-- Process NetworkVarElement calls
	local networkVarElementDiffs = NetworkVarProcessor.processNetworkVarElementCalls(text, global, class, config)
	for _, diff in ipairs(networkVarElementDiffs) do
		diffs[#diffs + 1] = diff
	end

	return diffs
end

	---Collects NetworkVar and NetworkVarElement docs as strings (no diffs), to be appended under a class doc
	---@param text string File content
	---@param global string|nil Global scope
	---@param class string|nil Class name
	---@param config table Configuration
	---@return string[] fieldDocs Documentation lines
	function NetworkVarProcessor.collectFieldDocs(text, global, class, config)
		local fieldDocs = {}
		local patterns = config.patterns or {}

		local networkVarCalls = NetworkVarProcessor.findNetworkVarCalls(text, patterns.networkVar)
		for _, call in ipairs(networkVarCalls) do
			local luaType = NetworkVarProcessor.resolveDtType(call.type, config)
			local selfType = class or global or "Entity"
			local docs = DocLines.formatNetworkVarPair(call.name, selfType, luaType)
			for _, line in ipairs(docs) do
				fieldDocs[#fieldDocs + 1] = line
			end
		end

		local networkVarElementCalls = NetworkVarProcessor.findNetworkVarElementCalls(text, patterns.networkVarElement)
		for _, call in ipairs(networkVarElementCalls) do
			local luaType = NetworkVarProcessor.resolveDtType(call.type, config)
			local selfType = class or global or "Entity"
			local docs = DocLines.formatNetworkVarPair(call.name, selfType, luaType)
			for _, line in ipairs(docs) do
				fieldDocs[#fieldDocs + 1] = line
			end
		end

		return fieldDocs
	end

---Processes NetworkVar calls in text
---@param text string File content
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@return table[] diffs Array of documentation diffs
function NetworkVarProcessor.processNetworkVarCalls(text, global, class, config)
	local diffs = {}
	local patterns = config.patterns or {}
	local networkVarPattern = patterns.networkVar

	-- Find all NetworkVar calls
	local networkVarCalls = NetworkVarProcessor.findNetworkVarCalls(text, networkVarPattern)

	for _, call in ipairs(networkVarCalls) do
		local diff = NetworkVarProcessor.createNetworkVarDocumentation(call, global, class, config, text)
		if diff then
			diffs[#diffs + 1] = diff
		end
	end

	return diffs
end

---Processes NetworkVarElement calls in text
---@param text string File content
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@return table[] diffs Array of documentation diffs
function NetworkVarProcessor.processNetworkVarElementCalls(text, global, class, config)
	local diffs = {}
	local patterns = config.patterns or {}
	local networkVarElementPattern = patterns.networkVarElement

	-- Find all NetworkVarElement calls
	local networkVarElementCalls = NetworkVarProcessor.findNetworkVarElementCalls(text, networkVarElementPattern)

	for _, call in ipairs(networkVarElementCalls) do
		local diff = NetworkVarProcessor.createNetworkVarElementDocumentation(call, global, class, config, text)
		if diff then
			diffs[#diffs + 1] = diff
		end
	end

	return diffs
end

---Finds NetworkVar calls in text
---@param text string File content
---@param pattern string Search pattern
---@return table[] calls Array of NetworkVar call info
function NetworkVarProcessor.findNetworkVarCalls(text, pattern)
	local calls = {}
	local raw = CallScanner.findCalls(text, pattern)
	for _, c in ipairs(raw) do
		local args = NetworkVarProcessor.parseNetworkVarArgs(c.argsText)
		if args and args.type and args.name then
			calls[#calls + 1] = { type = args.type, name = args.name, position = c.position }
		end
	end
	return calls
end

---Finds NetworkVarElement calls in text
---@param text string File content
---@param pattern string Search pattern
---@return table[] calls Array of NetworkVarElement call info
function NetworkVarProcessor.findNetworkVarElementCalls(text, pattern)
	local calls = {}
	local raw = CallScanner.findCalls(text, pattern)
	for _, c in ipairs(raw) do
		local args = NetworkVarProcessor.parseNetworkVarElementArgs(c.argsText)
		if args and args.type and args.name then
			calls[#calls + 1] = { type = args.type, name = args.name, index = args.index, position = c.position }
		end
	end
	return calls
end

---Parses NetworkVar arguments
---@param argsText string Arguments text
---@return table|nil args Parsed arguments
function NetworkVarProcessor.parseNetworkVarArgs(argsText)
	-- Parse NetworkVar("Type", "Name")
	local parts = ArgParser.splitArguments(argsText)

	if #parts < 2 then
		return nil
	end

	local typeStr = ArgParser.extractStringValue(parts[1])
	local nameStr = ArgParser.extractStringValue(parts[2])

	if not typeStr or not nameStr then
		return nil
	end

	return {
		type = typeStr,
		name = nameStr
	}
end

---Parses NetworkVarElement arguments
---@param argsText string Arguments text
---@return table|nil args Parsed arguments
function NetworkVarProcessor.parseNetworkVarElementArgs(argsText)
	-- Parse NetworkVarElement("Type", index, "Name")
	local parts = ArgParser.splitArguments(argsText)

	if #parts < 3 then
		return nil
	end

	local typeStr = ArgParser.extractStringValue(parts[1])
	local indexNum = ArgParser.extractNumericValue(parts[2])
	local nameStr = ArgParser.extractStringValue(parts[3])

	if not typeStr or not nameStr then
		return nil
	end

	return {
		type = typeStr,
		name = nameStr,
		index = indexNum
	}
end

---Creates documentation diff for NetworkVar
---@param call table NetworkVar call info
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@return table|nil diff Documentation diff
function NetworkVarProcessor.createNetworkVarDocumentation(call, global, class, config, text)
	-- Resolve the data type
	local luaType = NetworkVarProcessor.resolveDtType(call.type, config)

	-- Find insertion point at the start of the line containing the call
	local insertPos = call.position
	if text then
		local before = text:sub(1, math.max(insertPos - 1, 0))
		local lineStart = before:match(".*\n()") or 1
		insertPos = lineStart
	end

	-- Generate documentation using shared helper
	local selfType = class or global or "Entity"
	local docs = DocLines.formatNetworkVarPair(call.name, selfType, luaType)
	local docText = DocLines.toDiffText(docs)

	return {
		start = insertPos,
		finish = insertPos - 1,
		text = docText
	}
end

---Creates documentation diff for NetworkVarElement
---@param call table NetworkVarElement call info
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@return table|nil diff Documentation diff
function NetworkVarProcessor.createNetworkVarElementDocumentation(call, global, class, config, text)
	-- Resolve the data type
	local luaType = NetworkVarProcessor.resolveDtType(call.type, config)

	-- Find insertion point at the start of the line containing the call
	local insertPos = call.position
	if text then
		local before = text:sub(1, math.max(insertPos - 1, 0))
		local lineStart = before:match(".*\n()") or 1
		insertPos = lineStart
	end

	-- Generate documentation using shared helper
	local selfType = class or global or "Entity"
	local docs = DocLines.formatNetworkVarPair(call.name, selfType, luaType)
	local docText = DocLines.toDiffText(docs)

	return {
		start = insertPos,
		finish = insertPos - 1,
		text = docText
	}
end

---Resolves DT type to Lua type
---@param dtType string Data table type
---@param config table Configuration
---@return string luaType
function NetworkVarProcessor.resolveDtType(dtType, config)
	local dtTypes = config.dtTypes or {}
	return dtTypes[dtType] or "any"
end

---Checks if text contains NetworkVar calls
---@param text string File content
---@param patterns table Pattern configurations
---@return boolean hasNetworkVars
function NetworkVarProcessor.hasNetworkVars(text, patterns)
	local networkVarPattern = patterns.networkVar
	local networkVarElementPattern = patterns.networkVarElement

	return text:find(networkVarPattern) ~= nil or text:find(networkVarElementPattern) ~= nil
end

return NetworkVarProcessor
