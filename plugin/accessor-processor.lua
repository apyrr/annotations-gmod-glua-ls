--[[
	Handles AccessorFunc call processing and generates getter/setter documentation.

	Processes AccessorFunc(target, varKey, name, forceType) calls and generates:
	- Backing field documentation (if varKey provided)
	- Setter method documentation (Set<Name>)
	- Getter method documentation (Get<Name>)

	Supports force type resolution from config.accessorForceTypes mapping.
--]]

local DocLines = require("plugin.doc-lines")
local ArgParser = require("plugin.arg-parser")
local CallScanner = require("plugin.call-scanner")
local AccessorProcessor = {}

---Processes AccessorFunc calls in text and generates documentation diffs
---@param text string File content
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@return table[] diffs Array of documentation diffs
function AccessorProcessor.processAccessorFuncs(text, global, class, config)
	local result = AccessorProcessor.processAccessorFuncsWithFieldDocs(text, global, class, config)
	return result.diffs
end

---Processes AccessorFunc calls and returns both diffs and field documentation lines
---@param text string File content
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@return table result {diffs: table[], fieldDocs: string[]}
function AccessorProcessor.processAccessorFuncsWithFieldDocs(text, global, class, config)
	local diffs = {}
	local fieldDocs = {}
	local patterns = config.patterns or {}
	local accessorPattern = patterns.accessorFunc

	-- Find all AccessorFunc calls
	local accessorCalls = AccessorProcessor.findAccessorCalls(text, accessorPattern)

	for _, call in ipairs(accessorCalls) do
		local result = AccessorProcessor.createAccessorDocumentationWithFieldDocs(call, global, class, config)
		if result then
			diffs[#diffs + 1] = result.diff
			-- Collect field documentation lines
			for _, fieldDoc in ipairs(result.fieldDocs) do
				fieldDocs[#fieldDocs + 1] = fieldDoc
			end
		end
	end

	return {
		diffs = diffs,
		fieldDocs = fieldDocs
	}
end

---Finds AccessorFunc calls in text
---@param text string File content
---@param pattern string Search pattern
---@return table[] calls Array of accessor call info
function AccessorProcessor.findAccessorCalls(text, pattern)
	local calls = {}
	local raw = CallScanner.findCalls(text, pattern)
	for _, c in ipairs(raw) do
		local args = AccessorProcessor.parseAccessorArgs(c.argsText)
		if args and args.name then
			calls[#calls + 1] = {
				name = args.name,
				varKey = args.varKey,
				forceType = args.forceType,
				target = args
					.target,
				position = c.position
			}
		end
	end
	return calls
end

---Parses AccessorFunc arguments
---@param argsText string Arguments text
---@return table|nil args Parsed arguments
function AccessorProcessor.parseAccessorArgs(argsText)
	-- Parse AccessorFunc(target, varKey, name, forceType)
	local parts = ArgParser.splitArguments(argsText, { trackParentheses = true })

	if #parts < 3 then
		return nil
	end

	local target = parts[1]
	local varKey = parts[2]
	local name = parts[3]
	local forceType = parts[4]

	-- Extract string values using shared helper
	local nameStr = ArgParser.extractStringValue(name)
	local varKeyStr = ArgParser.extractStringValue(varKey)

	if not nameStr then
		return nil
	end

	return {
		target = target,
		varKey = varKeyStr,
		name = nameStr,
		forceType = forceType
	}
end

--Creates documentation diff for AccessorFunc
---@param call table Accessor call info
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@return table|nil diff Documentation diff

function AccessorProcessor.createAccessorDocumentation(call, global, class, config, text)
	local result = AccessorProcessor.createAccessorDocumentationWithFieldDocs(call, global, class, config)
	return result and result.diff or nil
end

---Creates documentation diff and field docs for AccessorFunc
---@param call table Accessor call info
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@return table|nil result {diff: table, fieldDocs: string[]}
function AccessorProcessor.createAccessorDocumentationWithFieldDocs(call, global, class, config)
	-- Determine the force type
	local forceTypeStr = AccessorProcessor.resolveForceType(call.forceType, config)

	-- Find insertion point (typically before the AccessorFunc call)
	local insertPos = call.position

	-- Generate documentation using shared helper
	local selfType = class or global or "table"
	local docs = DocLines.formatAccessorPair(call.name, selfType, forceTypeStr, call.varKey)
	local docText = DocLines.toDiffText(docs)

	return {
		diff = {
			start = insertPos - 1,
			finish = insertPos - 1,
			text = docText
		},
		fieldDocs = docs
	}
end

---Resolves the force type from AccessorFunc argument
---@param forceTypeArg string|nil Force type argument
---@param config table Configuration
---@return string resolvedType
function AccessorProcessor.resolveForceType(forceTypeArg, config)
	if not forceTypeArg then
		return "any"
	end

	-- Check if it's a named constant
	local constantName = forceTypeArg:match("([%a_][%w_]*)")
	if constantName then
		local forceTypes = config.accessorForceTypes or {}
		local resolvedType = forceTypes[constantName]
		if resolvedType then
			return resolvedType
		end
	end

	-- Check if it's a numeric constant
	local numValue = tonumber(forceTypeArg)
	if numValue then
		local numericTypes = {
			[0] = "any", -- FORCE_NONE
			[1] = "string", -- FORCE_STRING
			[2] = "number", -- FORCE_NUMBER
			[3] = "boolean", -- FORCE_BOOL
			[4] = "Angle", -- FORCE_ANGLE
			[5] = "Color", -- FORCE_COLOR
			[6] = "Vector", -- FORCE_VECTOR
		}
		return numericTypes[numValue] or "any"
	end

	return "any"
end

---Checks if text contains AccessorFunc calls
---@param text string File content
---@param patterns table Pattern configurations
---@return boolean hasAccessorFuncs
function AccessorProcessor.hasAccessorFuncs(text, patterns)
	local accessorPattern = patterns.accessorFunc
	return text:find(accessorPattern) ~= nil
end

---Processes AccessorFunc calls for a specific target
---@param text string File content
---@param target string Target identifier (e.g., "self", "ENT")
---@param global string|nil Global scope
---@param class string|nil Class name
---@param config table Configuration
---@return table[] diffs Array of documentation diffs
function AccessorProcessor.processAccessorFuncsForTarget(text, target, global, class, config, rangeStart, rangeEnd)
	local diffs = {}
	local patterns = config.patterns or {}
	local accessorPattern = patterns.accessorFunc

	-- Find AccessorFunc calls that target the specified identifier
	local accessorCalls = AccessorProcessor.findAccessorCalls(text, accessorPattern)

	for _, call in ipairs(accessorCalls) do
		-- Check if this call targets our identifier
		local withinRange = true
		if rangeStart or rangeEnd then
			local rs = rangeStart or 0
			local re = rangeEnd or math.huge
			withinRange = (call.position >= rs) and (call.position <= re)
		end

		if withinRange and (call.target == target or
				(global and call.target == global) or
				call.target == "self") then
			local diff = AccessorProcessor.createAccessorDocumentation(call, global, class, config, text)
			if diff then
				diffs[#diffs + 1] = diff
			end
		end
	end

	return diffs
end

return AccessorProcessor
