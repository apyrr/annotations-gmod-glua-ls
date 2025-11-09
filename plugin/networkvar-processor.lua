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

-- Track NetworkVar entries handled via OnSetText so the AST pass can avoid duplicates.
local handledByUri = {}

local function makeHandledKey(scope, name)
	if scope and scope ~= "" then
		return scope .. "::" .. name
	end
	return name
end

function NetworkVarProcessor.resetHandled(uri)
	if not uri then
		return
	end
	handledByUri[uri] = {}
end

function NetworkVarProcessor.markHandled(uri, scope, name)
	if not uri or not name then
		return
	end
	local bucket = handledByUri[uri]
	if not bucket then
		bucket = {}
		handledByUri[uri] = bucket
	end
	bucket[makeHandledKey(scope, name)] = true
end

function NetworkVarProcessor.wasHandled(uri, scope, name)
	if not uri or not name then
		return false
	end
	local bucket = handledByUri[uri]
	if not bucket then
		return false
	end
	local key = makeHandledKey(scope, name)
	if bucket[key] then
		return true
	end
	if scope and scope ~= "" then
		return bucket[name] or false
	end
	return false
end

-- Identify comment spans so scanners can ignore commented-out calls.
local function buildCommentRanges(text)
	local ranges = {}
	if type(text) ~= "string" or text == "" then
		return ranges
	end

	local len = #text
	local i = 1
	while i <= len do
		local ch = text:sub(i, i)
		if ch == '"' or ch == "'" then
			local delim = ch
			i = i + 1
			while i <= len do
				local curr = text:sub(i, i)
				if curr == '\\' then
					i = i + 2
				elseif curr == delim then
					i = i + 1
					break
				else
					i = i + 1
				end
			end
		elseif ch == '[' then
			local eq = 0
			local j = i + 1
			while text:sub(j, j) == '=' do
				eq = eq + 1
				j = j + 1
			end
			if text:sub(j, j) == '[' then
				j = j + 1
				local closePattern = "]" .. string.rep("=", eq) .. "]"
				local closeStart, closeEnd = text:find(closePattern, j, true)
				if closeStart then
					i = closeEnd + 1
				else
					i = len + 1
				end
			else
				i = i + 1
			end
		elseif ch == '-' and text:sub(i, i + 1) == "--" then
			local j = i + 2
			local eq = 0
			if text:sub(j, j) == '[' then
				j = j + 1
				while text:sub(j, j) == '=' do
					eq = eq + 1
					j = j + 1
				end
				if text:sub(j, j) == '[' then
					j = j + 1
					local closePattern = "]" .. string.rep("=", eq) .. "]"
					local closeStart, closeEnd = text:find(closePattern, j, true)
					if closeStart then
						ranges[#ranges + 1] = { start = i, finish = closeEnd }
						i = closeEnd + 1
					else
						ranges[#ranges + 1] = { start = i, finish = len }
						break
					end
					goto continue
				end
			end
			local newline = text:find("\n", j) or (len + 1)
			ranges[#ranges + 1] = { start = i, finish = newline - 1 }
			i = newline
		else
			i = i + 1
		end
		::continue::
	end

	return ranges
end

local function isPositionInRanges(ranges, pos)
	if not ranges or not pos then
		return false
	end
	for _, range in ipairs(ranges) do
		if pos < range.start then
			break
		end
		if pos <= range.finish then
			return true
		end
	end
	return false
end

---Processes NetworkVar calls in text and generates documentation diffs
---@param text string File content
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@param uri string|nil File URI for tracking handled entries
---@return table[] diffs Array of documentation diffs
function NetworkVarProcessor.processNetworkVars(text, global, class, config, uri)
	local diffs = {}
	local commentRanges = buildCommentRanges(text)

	-- Process NetworkVar calls
	local networkVarDiffs = NetworkVarProcessor.processNetworkVarCalls(text, global, class, config, uri, commentRanges)
	for _, diff in ipairs(networkVarDiffs) do
		diffs[#diffs + 1] = diff
	end

	-- Process NetworkVarElement calls
	local networkVarElementDiffs = NetworkVarProcessor.processNetworkVarElementCalls(text, global, class, config, uri,
		commentRanges)
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
---@param uri string|nil File URI for tracking handled entries
---@return string[] fieldDocs Documentation lines
function NetworkVarProcessor.collectFieldDocs(text, global, class, config, uri)
	local fieldDocs = {}
	local patterns = config.patterns or {}
	local commentRanges = buildCommentRanges(text)
	local scope = class or global

	local networkVarCalls = NetworkVarProcessor.findNetworkVarCalls(text, patterns.networkVar, commentRanges)
	for _, call in ipairs(networkVarCalls) do
		local luaType = NetworkVarProcessor.resolveDtType(call.type, config)
		local selfType = scope or "Entity"
		local docs = DocLines.formatNetworkVarPair(call.name, selfType, luaType)
		if uri then
			NetworkVarProcessor.markHandled(uri, scope, call.name)
		end
		for _, line in ipairs(docs) do
			fieldDocs[#fieldDocs + 1] = line
		end
	end

	local networkVarElementCalls = NetworkVarProcessor.findNetworkVarElementCalls(text, patterns.networkVarElement,
		commentRanges)
	for _, call in ipairs(networkVarElementCalls) do
		local luaType = NetworkVarProcessor.resolveDtType(call.type, config)
		local selfType = scope or "Entity"
		local docs = DocLines.formatNetworkVarPair(call.name, selfType, luaType)
		if uri then
			NetworkVarProcessor.markHandled(uri, scope, call.name)
		end
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
---@param uri string|nil File URI for tracking handled entries
---@param commentRanges table[]|nil Precomputed comment spans
---@return table[] diffs Array of documentation diffs
function NetworkVarProcessor.processNetworkVarCalls(text, global, class, config, uri, commentRanges)
	local diffs = {}
	local patterns = config.patterns or {}
	local networkVarPattern = patterns.networkVar
	if not networkVarPattern then
		return diffs
	end

	-- Find all NetworkVar calls
	local scope = class or global
	local networkVarCalls = NetworkVarProcessor.findNetworkVarCalls(text, networkVarPattern, commentRanges)

	for _, call in ipairs(networkVarCalls) do
		if uri then
			NetworkVarProcessor.markHandled(uri, scope, call.name)
		end
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
---@param uri string|nil File URI for tracking handled entries
---@param commentRanges table[]|nil Precomputed comment spans
---@return table[] diffs Array of documentation diffs
function NetworkVarProcessor.processNetworkVarElementCalls(text, global, class, config, uri, commentRanges)
	local diffs = {}
	local patterns = config.patterns or {}
	local networkVarElementPattern = patterns.networkVarElement
	if not networkVarElementPattern then
		return diffs
	end

	-- Find all NetworkVarElement calls
	local scope = class or global
	local networkVarElementCalls = NetworkVarProcessor.findNetworkVarElementCalls(text, networkVarElementPattern,
		commentRanges)

	for _, call in ipairs(networkVarElementCalls) do
		if uri then
			NetworkVarProcessor.markHandled(uri, scope, call.name)
		end
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
---@param commentRanges table[]|nil Precomputed comment spans
---@return table[] calls Array of NetworkVar call info
function NetworkVarProcessor.findNetworkVarCalls(text, pattern, commentRanges)
	local calls = {}
	if not pattern or pattern == "" then
		return calls
	end
	local ranges = commentRanges or buildCommentRanges(text)
	local raw = CallScanner.findCalls(text, pattern)
	for _, c in ipairs(raw) do
		if not isPositionInRanges(ranges, c.position) then
			local args = NetworkVarProcessor.parseNetworkVarArgs(c.argsText)
			if args and args.type and args.name then
				calls[#calls + 1] = { type = args.type, name = args.name, position = c.position }
			end
		end
	end
	return calls
end

---Finds NetworkVarElement calls in text
---@param text string File content
---@param pattern string Search pattern
---@param commentRanges table[]|nil Precomputed comment spans
---@return table[] calls Array of NetworkVarElement call info
function NetworkVarProcessor.findNetworkVarElementCalls(text, pattern, commentRanges)
	local calls = {}
	if not pattern or pattern == "" then
		return calls
	end
	local ranges = commentRanges or buildCommentRanges(text)
	local raw = CallScanner.findCalls(text, pattern)
	for _, c in ipairs(raw) do
		if not isPositionInRanges(ranges, c.position) then
			local args = NetworkVarProcessor.parseNetworkVarElementArgs(c.argsText)
			if args and args.type and args.name then
				calls[#calls + 1] = { type = args.type, name = args.name, index = args.index, position = c.position }
			end
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
