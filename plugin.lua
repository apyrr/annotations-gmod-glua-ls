--[[
	LuaLS plugin for Garry's Mod

	Includes code from https://github.com/TIMONz1535/glua-api-snippets/tree/plugin-wip1
	Includes code from https://github.com/CFC-Servers/luals_gmod_include

	This started as a project to combine both but ended up adding a bunch of new things and making a few fixes. It currently has:

	- Include Paths resolution
	- Scripted Class Detection (ENT, SWEP, EFFECT, TOOL) with automated class annotation and inheritance detection
	- DEFINE_BASECLASS processing
	- Derma Class automated annotation with inheritance detection
	- NetworkVar getter/setter annotation with type support
	- AccessorFunc getter/setter annotation with type support
	- Various fixes with class + hook inheritence (e.g PANEL and Panel caused issues)
	- config.lua to configure some stuff easily
--]]

local util = require("utility")
local client = require("client")
local log = require("log")
local guide = require("parser.guide")
local helper = require("plugins.astHelper")
local fs = require("bee.filesystem")

local Defaults = require("plugin.defaults")
local FolderDetection = require("plugin.folder-detection")
local DermaProcessor = require("plugin.derma-processor")
local AccessorProcessor = require("plugin.accessor-processor")
local NetworkVarProcessor = require("plugin.networkvar-processor")
local ScriptedClass = require("plugin.scripted-class")

-- Error Handling Utilities Module
local ErrorHandler = {}

---Safely executes a function and logs errors
---@param func function
---@param context string
---@return any|nil result, string|nil error
function ErrorHandler.safeCall(func, context)
	local ok, result = pcall(func)
	if not ok then
		log.error(context, tostring(result), util.dump(client.info.clientInfo))
		return nil, string.format("Error in %s: %s", context, tostring(result))
	end
	return result, nil
end

-- Use defaults from the Defaults module, mostly as fallback in-case config is missing stuff
local defaultScriptedScopes = Defaults.scopes

--[[
		Configuration Management Module

		Handles loading and merging of plugin configuration from config.lua.
		Provides type-safe configuration access with validation and default fallbacks.
		TODO: Just return the config table and change everything to use that, most of this is not required
	--]]
local ConfigManager = {}

-- Simple config cache
local configCache = nil

---@return table|nil
local function loadConfig()
	if configCache ~= nil then
		return configCache or nil
	end

	local cfg = ErrorHandler.safeCall(function()
		return require("config")
	end, "loadConfig")

	if cfg and type(cfg) == "table" then
		configCache = cfg
		return cfg
	end

	configCache = false
	return nil
end

---Merges default configuration with user configuration
---@param defaultConfig table
---@param configKey string
---@param validator? function
---@return table
function ConfigManager.getMergedConfig(defaultConfig, configKey, validator)
	local cfg = loadConfig()
	local merged = {}

	-- Copy defaults
	for k, v in pairs(defaultConfig) do
		merged[k] = v
	end

	-- Merge user config if available
	if cfg and type(cfg[configKey]) == "table" then
		for k, v in pairs(cfg[configKey]) do
			if not validator or validator(k, v) then
				merged[k] = v
			end
		end
	end

	return merged
end

---@return table
function ConfigManager.getScopes()
	local cfg = loadConfig()
	if cfg and type(cfg.scopes) == "table" then
		return cfg.scopes
	end
	return defaultScriptedScopes
end

local defaultDtTypes = Defaults.dtTypes
local defaultAccessorForceTypes = Defaults.accessorForceTypes

-- Validators for configuration merging
local function isValidStringPair(k, v)
	return type(k) == "string" and type(v) == "string" and v ~= ""
end

local function isValidBooleanPair(k, v)
	return type(k) == "string" and (v == true or v == false)
end

---@return table<string,string>
function ConfigManager.getDtTypes()
	return ConfigManager.getMergedConfig(defaultDtTypes, "dtTypes", isValidStringPair)
end

---@return table<string,string>
function ConfigManager.getAccessorForceTypes()
	return ConfigManager.getMergedConfig(defaultAccessorForceTypes, "accessorForceTypes", isValidStringPair)
end

-- Use defaults from the Defaults module
local defaultBaseGmodMap = Defaults.baseGmodMap

---@return table<string, boolean>
function ConfigManager.getBaseGmodMap()
	local merged = ConfigManager.getMergedConfig(defaultBaseGmodMap, "baseGmodMap", isValidBooleanPair)
	-- Convert keys to lowercase for case-insensitive matching
	local lowercased = {}
	for k, v in pairs(merged) do
		lowercased[k:lower()] = v
	end
	return lowercased
end

---Gets pattern configurations
---@return table
function ConfigManager.getPatterns()
	local cfg = loadConfig()
	if cfg and type(cfg.patterns) == "table" then
		return ConfigManager.getMergedConfig(Defaults.patterns, "patterns")
	end
	return Defaults.patterns
end

---Gets numeric mappings for AccessorFunc force types
---@return table
function ConfigManager.getAccessorForceTypesByNumber()
	return Defaults.accessorForceTypesByNumber
end

---@return table
function ConfigManager.getConfig()
	return {
		patterns = ConfigManager.getPatterns(),
		scopes = ConfigManager.getScopes(),
		dtTypes = ConfigManager.getDtTypes(),
		accessorForceTypes = ConfigManager.getAccessorForceTypes(),
		baseGmodMap = ConfigManager.getBaseGmodMap(),
		accessorForceTypesByNumber = ConfigManager.getAccessorForceTypesByNumber()
	}
end

local function findFolderBase(uri, global, class)
	local config = ConfigManager.getConfig()
	return FolderDetection.detectFolderStructure(uri, global, class, config)
end

-- Text Processing Utilities Module
local TextProcessor = {}

---Checks if a class documentation already exists in text
---@param text string
---@param className string
---@return boolean
function TextProcessor.hasExistingClassDoc(text, className)
	local pattern = "---@class%s+" .. className .. "[%s: ]"
	return string.find(text, pattern) ~= nil
end

-- Scans all class docs in the original text and returns a list of {className, insertAfter, tableVar}
-- tableVar is inferred from the next assignment line after the class doc (e.g., PANEL = {})
---@param text string
---@return table[] classDocs
local function FindAllClassDocs(text)
	local results = {}
	local idx = 1
	while true do
		local s, e, cls = text:find("---@class%s+([%w_%.]+)[%s:]", idx)
		if not s then break end
		local after = text:find("\n", e + 1) or e
		-- Look at the next non-empty line and try to parse a variable assignment at line start
		local rest = text:sub(after + 1)
		-- get first line
		local nl = rest:find("\n") or (#rest + 1)
		local nextLine = rest:sub(1, nl - 1)
		-- Allow blank line between class and table; if blank, peek one more line
		local consumed = nl
		if nextLine:match("^%s*$") then
			local rest2 = rest:sub(consumed + 1)
			local nl2 = rest2:find("\n") or (#rest2 + 1)
			nextLine = rest2:sub(1, nl2 - 1)
		end
		local tbl = nextLine:match("^%s*local%s+([%a_][%w_]*)%s*=") or nextLine:match("^%s*([%a_][%w_]*)%s*=")
		results[#results + 1] = { className = cls, insertAfter = after, tableVar = tbl }
		idx = e + 1
	end
	return results
end

---@param uri string
---@return string? global, string? class
local function GetScopedClass(uri)
	local scopes = ConfigManager.getScopes()
	return ScriptedClass.getScopedClass(uri, scopes)
end

---@class PluginDiff
---@field start integer # The number of bytes at the beginning of the replacement
---@field finish integer # The number of bytes at the end of the replacement
---@field text string   # Replacement text

---Processes scripted class detection and generates documentation
---@param uri string File URI
---@param text string File content
---@param global string Global scope
---@param class string Class name
---@return PluginDiff[] diffs Array of documentation diffs
local function processScriptedClassDiffs(uri, text, global, class)
	local diffs = {}
	local config = ConfigManager.getConfig()
	local patterns = config.patterns

	-- Check if this file has Derma panel registrations to avoid conflicts
	local hasDermaRegistrations = DermaProcessor.hasDermaRegistrations(text, patterns)

	local localPattern = "%f[%a]local%s+" .. global .. "%s*="
	local hasLocal = string.find(text, localPattern) ~= nil

	local folderBase = findFolderBase(uri, global, class)
	local baseIdent, baseString
	if folderBase then
		if folderBase.kind == "ident" then
			baseIdent = folderBase.value
		else
			baseString = folderBase.value
		end
	else
		baseString = text:match(global .. "%.Base%s*=%s[\"\']([%w_]*)[\"\']")
	end

	local parent = global
	local localText = ""
	if baseIdent then
		if baseIdent == global then
			parent = global
			if not hasLocal then
				localText = ("local %s = {}\n\n"):format(global)
			end
		else
			parent = baseIdent
			if not hasLocal then
				localText = ("local %s = %s\n\n"):format(global, baseIdent)
			end
		end
	elseif baseString then
		local baseMap = ConfigManager.getBaseGmodMap()
		if baseMap[baseString:lower()] then
			parent = global
		else
			parent = baseString
		end
		if not hasLocal then
			localText = ("local %s = {}\n\n"):format(global)
		end
	else
		if not hasLocal then
			localText = ("local %s = {}\n\n"):format(global)
		end
	end

	if class and not hasDermaRegistrations then
		local alreadyHasClassDoc = TextProcessor.hasExistingClassDoc(text, class)

		-- Process AccessorFunc calls for this scripted class (collect field docs to place under the class doc)
		local accessorResult = AccessorProcessor.processAccessorFuncsWithFieldDocs(text, global, class, config)
		local fieldDocs = accessorResult.fieldDocs
		-- Also collect NetworkVar/NetworkVarElement field docs to keep them under the class doc instead of inline
		local nvFieldDocs = NetworkVarProcessor.collectFieldDocs(text, global, class, config)
		for _, line in ipairs(nvFieldDocs) do
			fieldDocs[#fieldDocs + 1] = line
		end

		if not alreadyHasClassDoc then
			local classDoc = ("---@class %s : %s"):format(class, parent)
			if #fieldDocs > 0 then
				classDoc = classDoc .. "\n" .. table.concat(fieldDocs, "\n")
			end
			diffs[#diffs + 1] = {
				start = 1,
				finish = 0,
				text = classDoc .. "\n" .. localText,
			}
		else
			-- Class doc exists, append field docs right under the existing class line
			if #fieldDocs > 0 then
				local pattern = "---@class%s+" .. class .. "[%s:]"
				local s, e = text:find(pattern)
				if s then
					-- find end of the line
					local after = text:find("\n", e + 1) or e
					local toInsert = table.concat(fieldDocs, "\n") .. "\n"
					diffs[#diffs + 1] = {
						start = after + 1,
						finish = after,
						text = toInsert,
					}
				end
			end
			if localText ~= "" then
				-- Ensure local stub is present at file top if missing
				diffs[#diffs + 1] = {
					start = 1,
					finish = 0,
					text = localText,
				}
			end
		end
	else
		if localText ~= "" then
			diffs[#diffs + 1] = {
				start = 1,
				finish = 0,
				text = localText,
			}
		end
	end

	return diffs
end

---Processes DEFINE_BASECLASS replacements
---@param text string File content
---@return PluginDiff[] diffs Array of documentation diffs
local function processDefineBaseclass(text)
	local diffs = {}
	local idx = 1
	while true do
		local s, e, paren = text:find("DEFINE_BASECLASS%s*(%b())", idx)
		if not s then break end
		diffs[#diffs + 1] = {
			start = s,
			finish = e,
			text = "local BaseClass = baseclass.Get" .. paren .. "\n",
		}
		idx = e + 1
	end
	return diffs
end

local function insertPos(d)
	return d.start or ((d.finish or 0) + 1)
end

local function resolveDiffConflicts(allDiffs)
	local replacements = {}
	for _, d in ipairs(allDiffs) do
		if d.start and d.finish and d.finish >= d.start then
			replacements[#replacements + 1] = { s = d.start, e = d.finish }
		end
	end
	if #replacements == 0 then return end
	for _, d in ipairs(allDiffs) do
		if d.start and d.finish and d.finish < d.start then
			local p = d.start
			for i = 1, #replacements do
				local r = replacements[i]
				if p >= r.s and p <= r.e then
					d.start = r.e + 1
					d.finish = r.e
					break
				end
			end
		end
	end
end

local function collectAccessorLines(text, target, cls, config, rs, re)
	local collected = {}
	local acc = AccessorProcessor.processAccessorFuncsForTarget(text, target, nil, cls, config, rs, re)
	for _, ad in ipairs(acc or {}) do
		if ad.text and #ad.text > 0 then
			for line in ad.text:gmatch("[^\n]+") do
				collected[#collected + 1] = line
			end
		end
	end
	return collected
end

---@param uri string # File URI
---@param text string # File content
---@return PluginDiff[]|nil
function OnSetText(uri, text)
	local result = ErrorHandler.safeCall(function()
		---@type PluginDiff[]
		local diffs = {}
		local config = ConfigManager.getConfig()

		-- Handle scripted class (ENT/SWEP/EFFECT/TOOL) detection and localization
		local global, class = GetScopedClass(uri)
		if global then
			local scriptedDiffs = processScriptedClassDiffs(uri, text, global, class)
			for _, diff in ipairs(scriptedDiffs) do
				diffs[#diffs + 1] = diff
			end
		end

		-- Handle DEFINE_BASECLASS replacement
		local baseclassDiffs = processDefineBaseclass(text)
		for _, diff in ipairs(baseclassDiffs) do
			diffs[#diffs + 1] = diff
		end

		-- Handle Derma panels (vgui.Register and derma.DefineControl)
		local dermaDiffs = DermaProcessor.processDermaRegistrations(text, config)

		do
			local sorted = {}
			for i = 1, #dermaDiffs do sorted[i] = dermaDiffs[i] end
			table.sort(sorted, function(a, b) return insertPos(a) < insertPos(b) end)

			for idx, d in ipairs(sorted) do
				if type(d.text) == "string" and d.text:find("---@class", 1, true) then
					local cls = d.text:match("^%-%-%-@class%s+([%w_%.]+)") or d.text:match("^---@class%s+([%w_%.]+)")
					if cls then
						local lineStart = insertPos(d)
						-- Bound this class's scan range to right before the next class insertion
						local nextPos = (sorted[idx + 1] and insertPos(sorted[idx + 1])) or (#text + 1)
						local rs = lineStart
						local re = nextPos - 1

						-- Grab the table assignment line from original text at this position
						local rest = text:sub(lineStart)
						local nl = rest:find("\n") or (#rest + 1)
						local nextLine = rest:sub(1, nl - 1)
						if nextLine:match("^%s*$") then
							local rest2 = rest:sub(nl + 1)
							local nl2 = rest2:find("\n") or (#rest2 + 1)
							nextLine = rest2:sub(1, nl2 - 1)
						end
						local tbl = nextLine:match("^%s*local%s+([%a_][%w_]*)%s*=") or
							nextLine:match("^%s*([%a_][%w_]*)%s*=")


						local lines = {}
						-- Prefer the parsed table variable; fall back to PANEL and self to handle typical Derma patterns
						if tbl then
							for _, l in ipairs(collectAccessorLines(text, tbl, cls, config, rs, re)) do
								lines[#lines + 1] =
									l
							end
						end
						if #lines == 0 then
							for _, l in ipairs(collectAccessorLines(text, "PANEL", cls, config, rs, re)) do
								lines[#lines + 1] =
									l
							end
						end
						if #lines == 0 then
							for _, l in ipairs(collectAccessorLines(text, "self", cls, config, rs, re)) do
								lines[#lines + 1] =
									l
							end
						end

						if #lines > 0 then
							d.text = ("---@class %s : "):format(cls) ..
								(d.text:match(":%s*(.-)\n") or "Panel") .. "\n" .. table.concat(lines, "\n") .. "\n"
						end
					end
				end
			end
		end
		for _, diff in ipairs(dermaDiffs) do
			diffs[#diffs + 1] = diff
		end

		-- NetworkVar/AccessorFunc handling
		-- 1) Scripted classes: already appended under the class doc in processScriptedClassDiffs
		-- 2) Non-scripted: if class docs exist in file, append AccessorFunc/NetworkVar under each corresponding class
		--    based on the table immediately following that class; otherwise, for AccessorFunc skip (avoid inline)
		if not global then
			local classDocs = FindAllClassDocs(text)
			if classDocs and #classDocs > 0 then
				for _, cdoc in ipairs(classDocs) do
					local lines = {}
					if cdoc.tableVar and cdoc.className then
						-- AccessorFunc for this specific table var, but only include those that appear after this class doc
						-- and before the next class doc (closest class above behavior)
						local rs = cdoc.insertAfter + 1
						local re = #text
						-- find the next class doc start
						for _, nextDoc in ipairs(classDocs) do
							if nextDoc.insertAfter > cdoc.insertAfter then
								re = nextDoc.insertAfter
								break
							end
						end
						local accDiffs = AccessorProcessor.processAccessorFuncsForTarget(text, cdoc.tableVar, nil,
							cdoc.className, config, rs, re)
						for _, ad in ipairs(accDiffs or {}) do
							if ad.text and #ad.text > 0 then
								for line in ad.text:gmatch("[^\n]+") do
									lines[#lines + 1] = line
								end
							end
						end
						-- This might not be needed, since NetworkVar is entity only
						local nvLines = NetworkVarProcessor.collectFieldDocs and
							NetworkVarProcessor.collectFieldDocs(text, nil, cdoc.className, config) or {}
						for _, l in ipairs(nvLines) do lines[#lines + 1] = l end
					end
					if #lines > 0 then
						diffs[#diffs + 1] = {
							start = cdoc.insertAfter + 1,
							finish = cdoc.insertAfter,
							text = table.concat(lines, "\n") .. "\n",
						}
					end
				end
			else
				-- Skip if no class doc present
				local networkVarDiffs = NetworkVarProcessor.processNetworkVars(text, nil, nil, config)
				for _, diff in ipairs(networkVarDiffs) do diffs[#diffs + 1] = diff end
			end
		end

		-- Resolve overlapping diffs: prevent insertions from targeting the same span as replacements

		resolveDiffConflicts(diffs)

		-- Apply diffs from bottom to top to avoid offset shifts when inserting/replacing
		if #diffs > 1 then
			table.sort(diffs, function(a, b)
				local sa = a.start or 0
				local sb = b.start or 0
				return sa > sb
			end)
		end

		if #diffs == 0 then
			return nil
		end
		return diffs
	end, "OnSetText")

	-- Return result or nil on error
	return result
end

---@param ast any
---@param classNode any
---@param name string
---@param selfType string
---@param valueType string
---@param group table
---@return boolean|nil
local function addGetSetDocs(ast, classNode, name, selfType, valueType, group)
	local ok = helper.addDoc(ast, classNode, "field",
		("Set%s fun(self: %s, value: %s)"):format(name, selfType, valueType), group)
	if not ok then
		return false
	end
	ok = helper.addDoc(ast, classNode, "field", ("Get%s fun(self: %s): %s"):format(name, selfType, valueType), group)
	if not ok then
		return false
	end
end

---@param ast any
---@param classNode any
---@param source any
---@param group table
---@param isElement boolean
---@return boolean|nil
local function BindNetworkVar(ast, classNode, source, group, isElement)
	local args = guide.getParams(source)
	if not args or #args < (isElement and 4 or 3) then
		return
	end

	local argSelf = args[1]
	local targetSelf = guide.getSelfNode(argSelf)
	if not targetSelf then
		return
	end
	if targetSelf.node ~= classNode then
		targetSelf = guide.getSelfNode(targetSelf)
		if not targetSelf or targetSelf.node ~= classNode then
			return
		end
	end

	local argType = args[2]
	local argSlot = args[3]
	local argName = args[isElement and 5 or 4]

	if isElement then
		local argElement = args[4]
		if argSlot.type == "string" and argElement.type == "string" then
			argName = argElement
		end
	else
		if argSlot.type == "string" and (not argName or argName.type == "table") then
			argName = argSlot
		end
	end
	if not (argType and argType.type == "string" and argName and argName.type == "string") then
		return
	end

	local dtMap = ConfigManager.getDtTypes()
	local dtType = isElement and "number" or dtMap[argType[1]]
	local name = argName[1]
	if not dtType then
		return
	end

	return addGetSetDocs(ast, classNode, name, "Entity", dtType, group)
end



---@param tbl any
---@param wanted string
---@return any|nil
local function findClassNode(tbl, wanted)
	if type(tbl) ~= "table" then return nil end
	for i = 1, #tbl do
		local n = tbl[i]
		if n and n.type == "local" and guide.getKeyName(n) == wanted then
			return n
		end
	end
	for _, n in pairs(tbl) do
		if n and type(n) == "table" and n.type == "local" and guide.getKeyName(n) == wanted then
			return n
		end
	end
	return nil
end

---@param node any
---@return boolean
local function isInsideSetupDataTables(node)
	local p = node
	for _ = 1, 12 do
		if not p or not p.parent then
			break
		end
		p = p.parent
		if guide.getKeyName(p) == "SetupDataTables" then
			return true
		end
	end
	return false
end



---@param uri string
---@param ast any
---@param group table
---@return any|nil classNode, string|nil global, string|nil class
local function processScriptedClass(uri, ast, group)
	local global, class = GetScopedClass(uri)
	if not global then
		return nil, nil, nil
	end
	local classNode = findClassNode(ast, global)
	if not classNode then
		return nil, nil, nil
	end
	local ok = helper.addClassDoc and helper.addClassDoc(ast, classNode, class .. ": " .. global, group)
	if ok == false then
		return nil, nil, nil
	end
	-- Bind NetworkVar/NetworkVarElement calls inside SetupDataTables on this class
	ok = guide.eachSourceType(ast, "call", function(source)
		local targetMethod = source.node
		local targetName = guide.getKeyName(targetMethod)
		if targetName ~= "NetworkVar" and targetName ~= "NetworkVarElement" then
			return
		end
		if not isInsideSetupDataTables(source) then
			return
		end
		local targetSelf = targetMethod.node and guide.getSelfNode(targetMethod.node)
		if not targetSelf or targetSelf.node ~= classNode then
			return
		end
		return BindNetworkVar(ast, classNode, source, group, targetName == "NetworkVarElement")
	end)
	if ok == false then
		-- Do not abort other passes if NetworkVar binding fails
		return classNode, global, class
	end
	return classNode, global, class
end




---@param uri string # File URI
---@param ast any # File AST
---@return any|nil
function OnTransformAst(uri, ast)
	local group = {}
	processScriptedClass(uri, ast, group)
	-- Moved vgui panels and AccessorFunc processing to OnSetText, since it's easier to debug using the diff view.
	return ast
end

---@param uri string # The workspace or top-level URI
---@param name string # Argument of require()
---@return string[]|nil
function ResolveRequire(uri, name)
	if string.sub(name, -4) ~= ".lua" then
		return nil
	end

	-- See https://github.com/LuaLS/LuaLS.github.io/issues/48
	local _callingName, callingURI = debug.getlocal(5, 2)
	do
		assert(_callingName == "suri", "Something broke! Did LuaLS update?")
	end

	local callingDirURI = callingURI:match("^(.*)/[^/]*$")

	local relative = callingDirURI .. "/" .. name

	local relativePath = relative:sub(8)
	if fs.exists(relativePath) then
		return { relative }
	end

	local absolute = uri .. "/lua/" .. name
	return { absolute }
end
