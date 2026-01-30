--[[
	LuaLS plugin for Garry's Mod

	Includes code from https://github.com/TIMONz1535/glua-api-snippets/tree/plugin-wip1
	Includes code from https://github.com/CFC-Servers/luals_gmod_include

	This started as a project to combine both, but ended up adding a bunch of new things and making a few fixes.
--]]

local util = require("utility")
local client = require("client")
local log = require("log")
local guide = require("parser.guide")
local helper = require("plugins.astHelper")
local fs = require("bee.filesystem")
local vm = require("vm")
local workspace = require("workspace")
local fileUri = require("file-uri")
local ArgParser = require("plugin.arg-parser")
local Json = require("plugin.json")

local FolderDetection = require("plugin.folder-detection")
local DermaProcessor = require("plugin.derma-processor")
local AccessorProcessor = require("plugin.accessor-processor")
local NetworkVarProcessor = require("plugin.networkvar-processor")
local ScriptedClass = require("plugin.scripted-class")

local pluginUri = ...
local bootstrapWorkspaceUri = select(2, ...)
local rawPluginArgs = select(3, ...)

local function decodeFileUriSafe(uri)
	if type(uri) ~= "string" then
		return nil
	end
	local ok, result = pcall(fileUri.decode, uri)
	if ok then
		return result
	end
	return nil
end

local decodedBootstrapWorkspacePath = decodeFileUriSafe(bootstrapWorkspaceUri)

local pluginArgOptions, pluginArgRemainder = ArgParser.parsePluginOptions(rawPluginArgs, pluginUri)
if pluginArgOptions.configPath then
	pluginArgOptions.configPath = pluginArgOptions.configPath:match("^%s*(.-)%s*$")
	if pluginArgOptions.configPath == "" then
		pluginArgOptions.configPath = nil
	end
end

local PluginOptions = {
	configPath = pluginArgOptions.configPath,
	disableWorkspaceConfig = pluginArgOptions.disableWorkspaceConfig or false,
}

if pluginArgRemainder and #pluginArgRemainder > 0 then
	log.warn("plugin bootstrap", "unrecognised plugin arguments: " .. table.concat(pluginArgRemainder, ", "))
end

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

--[[
		Configuration Management Module

		Handles loading and merging of plugin configuration from config.lua.
		Provides type-safe configuration access with validation and default fallbacks.
	--]]
local ConfigManager = {}

local DEFAULT_ONLY_KEY = "__default_only"
local NO_WORKSPACE_KEY = "__no_workspace"

local defaultConfigCache = nil
local workspaceConfigCache = {}
local mergedConfigCache = {}
local workspaceWarnings = {}
local workspaceInfoLogged = {}
local missingUriWarningIssued = false

ConfigManager.PluginOptions = PluginOptions

local function loadDefaultConfig()
	if defaultConfigCache ~= nil then
		return defaultConfigCache
	end

	local function getPluginDir()
		local info = debug.getinfo(1, "S")
		local src = info and info.source or ""
		if type(src) == "string" and src:sub(1, 1) == '@' then
			src = src:sub(2)
		end
		local dir = src:match("^(.*)[/\\][^/\\]+$")
		return dir
	end

	local cfg = ErrorHandler.safeCall(function()
		local dir = getPluginDir()
		if not dir then
			error("unable to determine plugin directory for loading config.lua")
		end
		local path = dir .. "/config.lua"
		local chunk, lfErr = loadfile(path)
		if not chunk then
			error("failed to load config.lua at " .. path .. ": " .. tostring(lfErr))
		end
		local ok, mod = pcall(chunk)
		if not ok then
			error("error running config.lua: " .. tostring(mod))
		end
		return mod
	end, "loadDefaultConfig")

	if not cfg or type(cfg) ~= "table" then
		defaultConfigCache = nil
		error("plugin config.lua is missing or invalid (expected table)")
	end

	defaultConfigCache = cfg
	return cfg
end

local function isUriLike(value)
	return type(value) == "string" and value:match("^%a[%w+.-]*://") ~= nil
end

local function normalizeUri(uri)
	return ArgParser.normalizePluginIdentity(uri)
end

local function isArrayLike(tbl)
	if type(tbl) ~= "table" then
		return false
	end
	local hasNumeric = false
	for k in pairs(tbl) do
		if type(k) == "number" then
			hasNumeric = true
		else
			return false
		end
	end
	return hasNumeric
end

local function deepCopy(value, seen)
	if value == Json.null then
		return Json.null
	end
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return seen[value]
	end
	local copy = {}
	seen[value] = copy
	for k, v in pairs(value) do
		copy[deepCopy(k, seen)] = deepCopy(v, seen)
	end
	return copy
end

local function deepMerge(base, override)
	if override == Json.null then
		return nil
	end
	if type(base) ~= "table" then
		if override == nil then
			return base
		end
		if type(override) == "table" then
			return deepCopy(override)
		end
		return override
	end
	if type(override) ~= "table" then
		return override
	end
	if isArrayLike(override) then
		return deepCopy(override)
	end
	local result = deepCopy(base)
	for k, v in pairs(override) do
		if v == Json.null then
			result[k] = nil
		elseif type(v) == "table" and type(result[k]) == "table" and not isArrayLike(v) and not isArrayLike(result[k]) then
			result[k] = deepMerge(result[k], v)
		else
			result[k] = deepCopy(v)
		end
	end
	return result
end

local function joinPath(base, relative)
	if not base or not relative or relative == "" then
		return nil
	end
	local ok, combined = pcall(function()
		local rel = fs.path(relative)
		if rel:is_absolute() then
			return rel:string()
		end
		local basePath = fs.path(base)
		return (basePath / rel):string()
	end)
	if ok then
		return combined
	end
	if relative:match("^%a:[/\\]") or relative:match("^/") then
		return relative
	end
	local sep = package.config:sub(1, 1)
	local sanitizedBase = base:gsub("[/\\]+$", "")
	local sanitizedRel = relative:gsub("^[\\/]+", "")
	return sanitizedBase .. sep .. sanitizedRel
end

local function warnWorkspace(workspaceUri, message)
	local key = workspaceUri or "__none"
	if workspaceWarnings[key] then
		return
	end
	workspaceWarnings[key] = true
	log.warn("workspace config", message)
	if client and client.showMessage then
		pcall(client.showMessage, "Warning", message)
	end
end

function ConfigManager.resolveWorkspaceRoot(uri)
	local normalized = normalizeUri(uri)
	local bestUri = nil
	local bestLength = -1

	local folders = client.workspaceFolders
	if type(folders) == "table" then
		for _, folder in ipairs(folders) do
			if folder and type(folder.uri) == "string" then
				local candidateNorm = normalizeUri(folder.uri)
				if normalized and candidateNorm and normalized:sub(1, #candidateNorm) == candidateNorm then
					if #candidateNorm > bestLength then
						bestLength = #candidateNorm
						bestUri = folder.uri
					end
				end
			end
		end
	end

	if not bestUri then
		bestUri = bootstrapWorkspaceUri
	end

	if not bestUri then
		return nil, nil
	end

	local path = decodeFileUriSafe(bestUri)
	if not path and bestUri == bootstrapWorkspaceUri then
		path = decodedBootstrapWorkspacePath
	end

	return bestUri, path
end

local function resolveWorkspaceConfigPath(workspaceRootUri)
	local override = PluginOptions.configPath

	local function coerceToPath(value)
		if type(value) ~= "string" then
			return nil, nil
		end
		if isUriLike(value) then
			local decoded = decodeFileUriSafe(value)
			return decoded or value, value
		end
		return value, value
	end

	if override and override ~= "" then
		if override:match("^%a:[/\\]") or override:match("^/") then
			return override, override
		end
		local fsPath, descriptor = nil, override
		if isUriLike(override) then
			fsPath = decodeFileUriSafe(override)
			if fsPath then
				return fsPath, descriptor
			end
		end
		if workspace and workspace.getAbsolutePath then
			local ok, absolute = pcall(workspace.getAbsolutePath, workspaceRootUri, override)
			if ok and type(absolute) == "string" then
				local coerced, shown = coerceToPath(absolute)
				if coerced then
					return coerced, shown
				end
			end
		end
		local _, workspacePath = ConfigManager.resolveWorkspaceRoot(workspaceRootUri)
		if workspacePath then
			fsPath = joinPath(workspacePath, override)
		end
		return fsPath, descriptor
	end

	local defaultName = ".glua-api-snippets.json"
	local fsPath = nil

	if workspace and workspace.getAbsolutePath then
		local ok, absolute = pcall(workspace.getAbsolutePath, workspaceRootUri, defaultName)
		if ok and type(absolute) == "string" then
			local coerced, shown = coerceToPath(absolute)
			if coerced then
				return coerced, shown
			end
		end
	end

	local _, workspacePath = ConfigManager.resolveWorkspaceRoot(workspaceRootUri)
	if workspacePath then
		fsPath = joinPath(workspacePath, defaultName)
	end

	return fsPath, defaultName
end

function ConfigManager.loadWorkspaceConfig(workspaceRootUri)
	local key = workspaceRootUri or "__default"
	local cached = workspaceConfigCache[key]
	if cached then
		return cached.config
	end

	if PluginOptions.disableWorkspaceConfig then
		workspaceConfigCache[key] = { config = {}, path = nil }
		return workspaceConfigCache[key].config
	end

	if not workspaceRootUri then
		workspaceConfigCache[key] = { config = {}, path = nil }
		return workspaceConfigCache[key].config
	end

	local fsPath, descriptor = resolveWorkspaceConfigPath(workspaceRootUri)
	if not fsPath or fsPath == "" then
		workspaceConfigCache[key] = { config = {}, path = descriptor }
		return workspaceConfigCache[key].config
	end

	local normalizedPath = fsPath
	if isUriLike(fsPath) then
		normalizedPath = decodeFileUriSafe(fsPath) or fsPath
	end

	if not normalizedPath or not fs.exists(normalizedPath) then
		workspaceConfigCache[key] = { config = {}, path = normalizedPath }
		return workspaceConfigCache[key].config
	end

	local text, readErr = ErrorHandler.safeCall(function()
		local handle, err = io.open(normalizedPath, "r")
		if not handle then
			error(err or ("unable to open " .. normalizedPath))
		end
		local data = handle:read("*a")
		handle:close()
		return data
	end, "loadWorkspaceConfig:read")

	if not text then
		warnWorkspace(workspaceRootUri,
			string.format("Failed to read workspace config at %s: %s", descriptor or normalizedPath,
				readErr or "unknown error"))
		workspaceConfigCache[key] = { config = {}, path = normalizedPath }
		return workspaceConfigCache[key].config
	end

	local parsed, decodeErr = Json.decode(text)
	if not parsed then
		warnWorkspace(workspaceRootUri,
			string.format("Failed to parse workspace config %s: %s", descriptor or normalizedPath,
				decodeErr or "unknown error"))
		workspaceConfigCache[key] = { config = {}, path = normalizedPath }
		return workspaceConfigCache[key].config
	end

	if type(parsed) ~= "table" then
		warnWorkspace(workspaceRootUri,
			string.format("Workspace config %s must decode to a table", descriptor or normalizedPath))
		workspaceConfigCache[key] = { config = {}, path = normalizedPath }
		return workspaceConfigCache[key].config
	end

	workspaceConfigCache[key] = { config = parsed, path = normalizedPath }

	if not workspaceInfoLogged[key] then
		log.info(string.format("workspace override active (%s)", descriptor or normalizedPath))
		workspaceInfoLogged[key] = true
	end

	return workspaceConfigCache[key].config
end

function ConfigManager.getConfig(uri)
	local defaultCfg = loadDefaultConfig()
	if not uri then
		if not missingUriWarningIssued then
			log.warn("ConfigManager.getConfig called without a URI; workspace overrides are ignored for this request")
			missingUriWarningIssued = true
		end
		if mergedConfigCache[DEFAULT_ONLY_KEY] then
			return mergedConfigCache[DEFAULT_ONLY_KEY]
		end
		local copy = deepCopy(defaultCfg)
		mergedConfigCache[DEFAULT_ONLY_KEY] = copy
		return copy
	end

	local workspaceUri = select(1, ConfigManager.resolveWorkspaceRoot(uri))
	local key = workspaceUri or NO_WORKSPACE_KEY
	if mergedConfigCache[key] then
		return mergedConfigCache[key]
	end

	local workspaceCfg = ConfigManager.loadWorkspaceConfig(workspaceUri)
	local merged = deepMerge(defaultCfg, workspaceCfg) or {}
	mergedConfigCache[key] = merged
	return merged
end

function ConfigManager.getScopes(uri)
	local cfg = ConfigManager.getConfig(uri)
	local scopes = cfg.scopes
	if type(scopes) ~= "table" then
		error("config.scopes must be a table")
	end
	return scopes
end

function ConfigManager.getDtTypes(uri)
	local cfg = ConfigManager.getConfig(uri)
	local dtTypes = cfg.dtTypes
	if type(dtTypes) ~= "table" then
		error("config.dtTypes must be a table")
	end
	return dtTypes
end

function ConfigManager.getAccessorForceTypes(uri)
	local cfg = ConfigManager.getConfig(uri)
	local forceTypes = cfg.accessorForceTypes
	if type(forceTypes) ~= "table" then
		error("config.accessorForceTypes must be a table")
	end
	return forceTypes
end

function ConfigManager.getBaseGmodMap(uri)
	local cfg = ConfigManager.getConfig(uri)
	local src = cfg.baseGmodMap
	if type(src) ~= "table" then
		error("config.baseGmodMap must be a table")
	end
	local lowercased = {}
	for k, v in pairs(src) do
		if type(k) == "string" then
			lowercased[k:lower()] = v
		end
	end
	return lowercased
end

function ConfigManager.getPatterns(uri)
	local cfg = ConfigManager.getConfig(uri)
	local patterns = cfg.patterns
	if type(patterns) ~= "table" then
		error("config.patterns must be a table")
	end
	return patterns
end

function ConfigManager.getAccessorForceTypesByNumber(uri)
	local cfg = ConfigManager.getConfig(uri)
	local numeric = cfg.accessorForceTypesByNumber
	if type(numeric) ~= "table" then
		error("config.accessorForceTypesByNumber must be a table")
	end
	local hasStringKey = false
	for k in pairs(numeric) do
		if type(k) == "string" then
			hasStringKey = true
			break
		end
	end
	if not hasStringKey then
		return numeric
	end
	local normalized = {}
	for k, v in pairs(numeric) do
		if type(k) == "string" then
			local num = tonumber(k)
			if num then
				normalized[num] = v
			else
				normalized[k] = v
			end
		else
			normalized[k] = v
		end
	end
	return normalized
end

function ConfigManager.getParamNameTypes(uri)
	local cfg = ConfigManager.getConfig(uri)
	local mappings = cfg.paramNameTypes
	if type(mappings) ~= "table" then
		return {}
	end
	return mappings
end

function ConfigManager._resetForTests()
	defaultConfigCache = nil
	workspaceConfigCache = {}
	mergedConfigCache = {}
	workspaceWarnings = {}
	workspaceInfoLogged = {}
	missingUriWarningIssued = false
end

local function findFolderBase(uri, global, class, config)
	local cfg = config or ConfigManager.getConfig(uri)
	return FolderDetection.detectFolderStructure(uri, global, class, cfg)
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
local function FindAllClassDocs(text, patterns)
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
		local localPat = (patterns and patterns.localGlobal) or "%f[%a]local%s+([%a_][%w_]*)%s*="
		local varAssign = (patterns and patterns.variableAssignment) or "([%a_][%w_]*)%s*=%s*"
		local tbl = nextLine:match("^%s*" .. localPat)
		if not tbl then
			tbl = nextLine:match("^%s*" .. varAssign)
		end
		results[#results + 1] = { className = cls, insertAfter = after, tableVar = tbl }
		idx = e + 1
	end
	return results
end

---@param uri string
---@return string? global, string? class
local function GetScopedClass(uri, config)
	local scopes = (config and config.scopes) or ConfigManager.getScopes(uri)
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
local function processScriptedClassDiffs(uri, text, global, class, config)
	local diffs = {}
	local cfg = config or ConfigManager.getConfig(uri)
	local patterns = cfg.patterns

	-- Check if this file has Derma panel registrations to avoid conflicts
	local hasDermaRegistrations = DermaProcessor.hasDermaRegistrations(text, patterns)

	local localByNameTpl = (patterns and patterns.localGlobalByNameTemplate) or "%f[%a]local%s+{name}%s*="
	local localPattern = localByNameTpl:gsub("{name}", global)
	local hasLocal = text:find(localPattern) ~= nil

	local folderBase = findFolderBase(uri, global, class, cfg)
	local baseIdent, baseString
	if folderBase then
		if folderBase.kind == "ident" then
			baseIdent = folderBase.value
		else
			baseString = folderBase.value
		end
	else
		-- Use configured patterns to detect base assignment in current file as a fallback
		local baseIdentPattern = (patterns and patterns.baseAssignment) or "([%a_][%w_]*)%.%s*Base%s*=%s*([%a_][%w_%.]*)"
		local baseStringPattern = (patterns and patterns.baseStringAssignment) or
			"([%a_][%w_]*)%.%s*Base%s*=%s*[\"']([^\"']+)[\"']"
		local var, ident = text:match(baseIdentPattern)
		if var == global and ident and ident ~= "" then
			baseIdent = ident
		else
			local var2, bstr = text:match(baseStringPattern)
			if var2 == global and bstr and bstr ~= "" then
				baseString = bstr
			end
		end
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
		local baseMap = ConfigManager.getBaseGmodMap(uri)
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

		local accessorResult = AccessorProcessor.processAccessorFuncsWithFieldDocs(text, global, class, cfg)
		local fieldDocs = accessorResult.fieldDocs
		local nvFieldDocs = NetworkVarProcessor.collectFieldDocs(text, global, class, cfg, uri)
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
			if #fieldDocs > 0 then
				local pattern = "---@class%s+" .. class .. "[%s:]"
				local s, e = text:find(pattern)
				if s then
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
local function processDefineBaseclass(uri, text, config)
	local diffs = {}
	local idx = 1
	-- Use configured pattern for DEFINE_BASECLASS
	local cfg = config or ConfigManager.getConfig(uri)
	local definePat = (cfg.patterns and cfg.patterns.defineBaseclass) or "DEFINE_BASECLASS%s*(%b())"
	while true do
		local s, e, paren = text:find(definePat, idx)
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
		local config = ConfigManager.getConfig(uri)
		NetworkVarProcessor.resetHandled(uri)

		-- Skip meta files
		if type(text) == "string" and text:match("^%-%-%-@meta") then
			return nil
		end

		-- Handle scripted class (ENT/SWEP/EFFECT/TOOL) detection and localization
		local global, class = GetScopedClass(uri, config)
		if global then
			local scriptedDiffs = processScriptedClassDiffs(uri, text, global, class, config)
			for _, diff in ipairs(scriptedDiffs) do
				diffs[#diffs + 1] = diff
			end
		end

		-- Handle DEFINE_BASECLASS replacement
		local baseclassDiffs = processDefineBaseclass(uri, text, config)
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
						local localPat2 = (config.patterns and config.patterns.localGlobal) or
							"%f[%a]local%s+([%a_][%w_]*)%s*="
						local varAssign2 = (config.patterns and config.patterns.variableAssignment) or
							"([%a_][%w_]*)%s*=%s*"
						local tbl = nextLine:match("^%s*" .. localPat2) or nextLine:match("^%s*" .. varAssign2)


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
			local classDocs = FindAllClassDocs(text, config.patterns)
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
							NetworkVarProcessor.collectFieldDocs(text, nil, cdoc.className, config, uri) or {}
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
				local networkVarDiffs = NetworkVarProcessor.processNetworkVars(text, nil, nil, config, uri)
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
local function BindNetworkVar(ast, classNode, source, group, isElement, config, uri, className, globalName)
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

	local dtMap = (config and config.dtTypes) or ConfigManager.getDtTypes(uri)
	local dtType = isElement and "number" or dtMap[argType[1]]
	local name = argName[1]
	if not dtType then
		return
	end

	local scopeName = className or globalName
	if NetworkVarProcessor.wasHandled and NetworkVarProcessor.wasHandled(uri, scopeName, name) then
		return
	end

	return addGetSetDocs(ast, classNode, name, scopeName or "Entity", dtType, group)
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

-- Helper to inspect function definitions for NetworkVar calls inside SetupDataTables
local function findNetworkVarWrappers(ast)
	local wrappers = {}

	guide.eachSourceType(ast, "function", function(funcNode)
		-- Get the name of this function
		local parent = funcNode.parent
		if not parent then return end
		-- guide.getKeyName works for methods/fields; [1] is the name for local/global identifiers
		local wrapperName = guide.getKeyName(parent) or (parent.type == "local" and parent[1]) or
			(parent.type == "setglobal" and parent[1])
		if not wrapperName then return end
		local isMethodDefinition = parent.type == "setmethod"

		-- Check calls inside the function
		guide.eachSourceType(funcNode, "call", function(callNode)
			local method = callNode.node
			local methodName = guide.getKeyName(method)
			if methodName ~= "NetworkVar" and methodName ~= "NetworkVarElement" then return end

			local args = guide.getParams(callNode)
			-- args: [self, type, slot/index, name, ...]
			if not args or #args < 3 then return end

			local info = {}

			local typeArg = args[2]
			if typeArg and typeArg.type == "string" then
				info.fixedType = typeArg[1]
			end

			if not info.fixedType then return end

			-- We prioritize arguments in reverse (name -> element -> slot) as name is usually the last relevant arg.
			local isElement = methodName == "NetworkVarElement"
			info.isElement = isElement
			local searchIndices = isElement and { 5, 4, 3 } or { 4, 3 }
			local paramParams = guide.getParams(funcNode) or {}

			for _, argIdx in ipairs(searchIndices) do
				local argNode = args[argIdx]
				if argNode then
					if argNode.type == "getlocal" then
						for i, p in ipairs(paramParams) do
							if p == argNode.node then
								info.nameParamIndex = i
								if isMethodDefinition then
									info.wrapperIsMethod = true
								elseif i > 1 and paramParams[1] and (paramParams[1][1] == "self" or guide.getKeyName(paramParams[1]) == "self") then
									info.wrapperIsMethod = true
								end
								break
							end
						end
					elseif argNode.type == "string" then
						info.fixedName = argNode[1]
					end
				end
				if info.nameParamIndex or info.fixedName then break end
			end

			if info.nameParamIndex or info.fixedName then
				wrappers[wrapperName] = info
			end
		end)
	end)

	return wrappers
end


---@param uri string
---@param ast any
---@param group table
---@return any|nil classNode, string|nil global, string|nil class
local function processScriptedClass(uri, ast, group, config)
	local global, class = GetScopedClass(uri, config)
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
	-- Scan for local wrapper functions that internally call NetworkVar
	local wrappers = findNetworkVarWrappers(ast)
	-- Bind NetworkVar/NetworkVarElement calls inside SetupDataTables on this class
	ok = guide.eachSourceType(ast, "call", function(source)
		local targetMethod = source.node
		local targetName = guide.getKeyName(targetMethod) or (targetMethod.type == "getlocal" and targetMethod[1]) or
			(targetMethod.type == "getglobal" and targetMethod[1])
		if not isInsideSetupDataTables(source) then
			return
		end
		if targetName == "NetworkVar" or targetName == "NetworkVarElement" then
			local targetSelf = targetMethod.node and guide.getSelfNode(targetMethod.node)
			if not targetSelf or targetSelf.node ~= classNode then
				targetSelf = guide.getSelfNode(targetSelf)
				if not targetSelf or targetSelf.node ~= classNode then
					return
				end
			end
			return BindNetworkVar(ast, classNode, source, group, targetName == "NetworkVarElement", config, uri, class,
				global)
		elseif wrappers[targetName] then
			local info = wrappers[targetName]
			local args = guide.getParams(source)
			if not args then return end

			local callIsMethod = (targetMethod and (targetMethod.type == "method" or targetMethod.type == "getmethod"))
			if callIsMethod then
				local targetSelf = targetMethod.node and guide.getSelfNode(targetMethod.node)
				if not targetSelf or targetSelf.node ~= classNode then
					targetSelf = guide.getSelfNode(targetSelf)
					if not targetSelf or targetSelf.node ~= classNode then
						return
					end
				end
			end

			local typeStr = info.fixedType
			local nameStr = info.fixedName

			if info.nameParamIndex then
				-- Account for 'self' potentially being different between definition and call
				local defOffset = info.wrapperIsMethod and 1 or 0
				local callOffset = callIsMethod and 1 or 0
				local function resolveNameAt(index)
					if index > 0 and index <= #args then
						local nameArg = args[index]
						if nameArg and nameArg.type == "string" then
							return nameArg[1]
						end
					end
				end

				local relativeIndex = info.nameParamIndex - defOffset + callOffset
				local resolvedName = resolveNameAt(relativeIndex)
				if not resolvedName then
					local altDefOffset = defOffset == 1 and 0 or 1
					resolvedName = resolveNameAt(info.nameParamIndex - altDefOffset + callOffset)
				end
				if resolvedName then
					nameStr = resolvedName
				end
			end

			if typeStr and nameStr then
				local dtMap = (config and config.dtTypes) or ConfigManager.getDtTypes(uri)
				local luaType = info.isElement and "number" or (dtMap[typeStr] or "any")

				local scopeName = class or global
				if NetworkVarProcessor.wasHandled and NetworkVarProcessor.wasHandled(uri, scopeName, nameStr) then
					return
				end

				return addGetSetDocs(ast, classNode, nameStr, scopeName or "Entity", luaType, group)
			end
		end
	end)
	if ok == false then
		-- Do not abort other passes if NetworkVar binding fails
		return classNode, global, class
	end
	return classNode, global, class
end


-- Determine if a setlocal assignment resets PANEL to a fresh table (including setmetatable({})).
local function isTableResetAssign(set)
	if not set or set.type ~= "setlocal" then return false end
	local v = set.value
	if not v then return false end
	if v.type == "table" then return true end
	if v.type == "call" then
		local callee = v.node
		if callee and callee.special == 'setmetatable' and v.args and v.args[1] and v.args[1].type == 'table' then
			return true
		end
	end
	return false
end

-- Split reused `PANEL` locals, to make each `PANEL = {}` register as a new variable
-- This fixes a LuaLS bug, where re-using the variable in the same file would cause it to believe it's a global
-- This only really impacts panels, so we've hard-coded it to that for now.
local function splitReusedPanelLocals(astRoot)
	guide.eachSourceType(astRoot, "local", function(loc)
		if loc[1] ~= "PANEL" then return end
		local block = loc.parent
		if type(block) ~= 'table' then return end

		-- Collect all refs currently bound to this local
		local refs = {}
		guide.eachSourceTypes(astRoot, { 'getlocal', 'setlocal' }, function(ref)
			if ref.node == loc then
				refs[#refs + 1] = ref
			end
		end)
		if #refs == 0 then return end
		table.sort(refs, function(a, b) return a.start < b.start end)

		-- Identify all table-reset assignments to PANEL (PANEL = {})
		local resets = {}
		for _, r in ipairs(refs) do
			if isTableResetAssign(r) then
				resets[#resets + 1] = r
			end
		end
		if #resets == 0 then return end

		table.sort(resets, function(a, b) return a.start < b.start end)

		-- Create Segments: base (original local), then one segment per reset with a new local
		local segments = {}
		segments[#segments + 1] = { from = loc.effect or loc.start or 0, at = loc }

		block.locals = block.locals or {}

		for i = 1, #resets do
			local reset = resets[i]
			---@type table
			local newLoc = {
				type   = 'local',
				parent = block,
				[1]    = 'PANEL',
				start  = reset.start,
				finish = reset.finish,
				effect = reset.start,
				value  = reset.value,
				attrs  = nil,
				ref    = {},
			}
			if newLoc.value then newLoc.value.parent = newLoc end
			block.locals[#block.locals + 1] = newLoc
			segments[#segments + 1] = { from = newLoc.effect, at = newLoc }
		end

		table.sort(block.locals, function(a, b)
			return (a.effect or a.start or 0) < (b.effect or b.start or 0)
		end)
		table.sort(segments, function(a, b) return a.from < b.from end)

		local function pickSegment(pos)
			local chosen = segments[1]
			for i = 1, #segments do
				if pos >= segments[i].from then
					chosen = segments[i]
				else
					break
				end
			end
			return chosen.at
		end

		-- Rebind refs to the correct segment-local
		local refListsByLocal = {}
		for _, ref in ipairs(refs) do
			local tgt = pickSegment(ref.start)
			if ref.node ~= tgt then
				ref.node = tgt
			end
			refListsByLocal[tgt] = refListsByLocal[tgt] or {}
			refListsByLocal[tgt][#refListsByLocal[tgt] + 1] = ref
		end

		-- Update locals' ref arrays (best-effort)
		loc.ref = refListsByLocal[loc]
		for i = 2, #segments do
			local l = segments[i].at
			l.ref = refListsByLocal[l]
		end
	end)
end


---@param uri string # File URI
---@param ast any # File AST
---@return any|nil
function OnTransformAst(uri, ast)
	local group = {}
	local config = ConfigManager.getConfig(uri)
	processScriptedClass(uri, ast, group, config)
	-- Moved vgui panels and AccessorFunc processing to OnSetText, since it's easier to debug using the diff view.

	-- Split reused PANEL locals across table resets once per transform.
	-- This is to fix a LuaLS bug with constant PANEL definitions
	splitReusedPanelLocals(ast)
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

local function resolveUriFromNode(node, visited)
	local nodeType = type(node)
	if nodeType == "string" then
		if isUriLike(node) or node:match("[\\/]") then
			return node
		end
		return nil
	end
	if nodeType ~= "table" then
		return nil
	end
	visited = visited or {}
	if visited[node] then
		return nil
	end
	visited[node] = true

	if type(node.uri) == "string" then
		return node.uri
	end
	if type(node.source) == "string" then
		if isUriLike(node.source) then
			return node.source
		end
	elseif type(node.source) == "table" then
		local uri = resolveUriFromNode(node.source, visited)
		if uri then
			return uri
		end
	end
	if type(node.node) == "table" then
		local uri = resolveUriFromNode(node.node, visited)
		if uri then
			return uri
		end
	end
	if type(node.parent) == "table" then
		local uri = resolveUriFromNode(node.parent, visited)
		if uri then
			return uri
		end
	end
	return nil
end

-- Smart parameter inference using VM.OnCompileFunctionParam
-- Provides best-effort typing for function parameters based on
-- common parameter name patterns defined in `config.paramNameTypes`.
-- This hook calls the default compiler behavior first and only attempts
-- to infer when no type was determined.
function OnCompileFunctionParam(next, func, param)
	-- Call default first. Only attempt inference if default did not resolve the type.
	if next and next(func, param) then
		return true
	end

	local source = param and (param.node or param.source or param)
	if not source then return nil end

	local inferredUri = resolveUriFromNode(param) or resolveUriFromNode(func) or bootstrapWorkspaceUri
	local mappings = ConfigManager.getParamNameTypes(inferredUri)

	local name
	if type(source) == "table" then
		name = source.name or source[1] or source[2]
	elseif type(source) == "string" then
		name = source
	end
	if not name or type(name) ~= "string" then return nil end

	local lname = name:lower()
	local typ = mappings[lname]
	if typ then
		local declared = vm.declareGlobal('type', typ, nil)
		if declared then
			vm.setNode(source, vm.createNode(declared, source))
			return true
		end
	end
	return nil
end

-- VM.OnCompileFunctionParam is weird, for some reason this fixes the errors?
VM = VM or {}
VM.OnCompileFunctionParam = OnCompileFunctionParam
