-- Combined LuaLS plugin for Garry's Mod
-- Uses code from:
-- 1) https://github.com/TIMONz1535/glua-api-snippets/tree/plugin-wip1 (plugin.lua)
-- 2) https://github.com/CFC-Servers/luals_gmod_include (plugin.lua)
-- Adds: Proper Include Paths,

local guide = require "parser.guide"
local helper = require "plugins.astHelper"
local fs = require("bee.filesystem")

local existsCache = {}

--- Check if a file URI exists (file:///...)
--- @param uri string
--- @return boolean
local function uriExists(uri)
	local cached = existsCache[uri]
	if cached ~= nil then
		return cached
	end
	-- Remove 'file:///' prefix
	local path = uri:sub(8)
	local exists = fs.exists(path)
	existsCache[uri] = exists
	return exists
end

-- Simple file read helper for file:/// URIs
local function readUriText(uri)
	local path = uri:sub(8)
	local f, err = io.open(path, "r")
	if not f then
		return nil
	end
	local content = f:read("*a")
	f:close()
	return content
end

local folderBaseCache = {}

-- Attempt to find <GLOBAL>.Base inside the class folder (shared/init files)
-- Returns a table { kind = "ident"|"string", value = string } or nil
local function findFolderBase(uri, global, class)
	-- Determine calling directory and filename
	local callingDir = uri:match("^(.*)/[^/]*$")
	if not callingDir then
		return nil
	end
	local fileName = uri:match("[^/]+$") or ""
	fileName = fileName:lower()

	-- Decide whether this file is part of a folder-based class
	local commonHub = {
		["shared.lua"] = true,
		["init.lua"] = true,
		["cl_init.lua"] = true,
	}

	local folderPath
	if commonHub[fileName] then
		folderPath = callingDir
	else
		-- If parent directory name equals class, treat dir as class folder
		local parentName = callingDir:match("([^/]+)$")
		if parentName and parentName == class then
			folderPath = callingDir
		else
			return nil
		end
	end

	-- Use cache key = folderPath
	local cached = folderBaseCache[folderPath]
	if cached ~= nil then
		return cached
	end

	-- Default files to check for
	local candidates = {
		folderPath .. "/shared.lua",
		folderPath .. "/init.lua",
		folderPath .. "/cl_init.lua",
	}

	for _, c in ipairs(candidates) do
		if uriExists(c) then
			local txt = readUriText(c)
			if txt then
				local ident = txt:match(global .. "%..-%s*Base%s*=%s*([%a_][%w_%.]*)")
				if ident then
					local res = { kind = "ident", value = ident }
					folderBaseCache[folderPath] = res
					return res
				end
				local s = txt:match(global .. "%..-%s*Base%s*=%s*[\"']([^\"']+)[\"']")
				if s then
					local res = { kind = "string", value = s }
					folderBaseCache[folderPath] = res
					return res
				end
			end
		end
	end

	-- No base found
	folderBaseCache[folderPath] = nil
	return nil
end

-- Default scopes, can be overridden via plugin.config.lua, only here incase of missing config
local defaultScriptedScopes = {
	{ global = "ENT",    folder = "entities" },
	{ global = "SWEP",   folder = "weapons" },
	{ global = "EFFECT", folder = "effects" },
	{ global = "TOOL",   folder = "weapons/gmod_tool/stools" },
}

-- Load from plugin.config.lua
local pluginConfig --[[@type table|false|nil]]

--- Get directory path to this plugin file
--- @return string|nil
local function getPluginDir()
	local src
	local ok, info = pcall(debug.getinfo, 1, "S")
	if ok and info and info.source then
		src = info.source
	else
		return nil
	end
	if src:sub(1, 1) == '@' then
		src = src:sub(2)
	end
	if src:sub(1, 8) == "file:///" then
		src = src:sub(9)
	end
	src = src:gsub("\\", "/")
	return src:match("^(.*)/[^/]*$")
end

--- Attempt to load plugin.config.lua
--- @return table|nil
local function loadConfig()
	if pluginConfig ~= nil then
		return pluginConfig or nil
	end
	local dir = getPluginDir()
	if not dir then
		pluginConfig = false
		return nil
	end
	local path = dir .. "/plugin.config.lua"
	local ok, cfg = pcall(dofile, path)
	if ok and type(cfg) == "table" then
		pluginConfig = cfg
		return cfg
	end
	pluginConfig = false
	return nil
end

--- Get configured scopes or fall back to defaults
--- @return table
local function getScopes()
	local cfg = loadConfig()
	if cfg and type(cfg.scopes) == "table" then
		return cfg.scopes
	end
	return defaultScriptedScopes
end

--- Default NetworkVar type mapping, can be overridden via plugin.config.lua, only here incase of missing config
local defaultDtTypes = {
	String = "string",
	Bool   = "boolean",
	Float  = "number",
	Int    = "integer",
	Vector = "Vector",
	Angle  = "Angle",
	Entity = "Entity",
}

--- Get configured dtTypes or fall back to defaults; merge (config wins)
--- @return table<string,string>
local function getDtTypes()
	local cfg = loadConfig()
	local merged = {}
	for k, v in pairs(defaultDtTypes) do merged[k] = v end
	if cfg and type(cfg.dtTypes) == "table" then
		for k, v in pairs(cfg.dtTypes) do
			if type(k) == "string" and type(v) == "string" and v ~= "" then
				merged[k] = v
			end
		end
	end
	return merged
end

--- Default entity bases, can be overridden via plugin.config.lua, only here incase of missing config
--- This is used to determine if we should inherit an entity from ENT instead of the literal string used for the base class
local defaultBaseGmodMap = {
	["base_gmodentity"] = true,
	["base_anim"] = true,
	["base_ai"] = true,
	["base_nextbot"] = true,
}

--- Get configured baseGmodMap or fall back to defaults; merge (config wins)
--- @return table<string, boolean>
local function getBaseGmodMap()
	local cfg = loadConfig()
	local merged = {}
	for k, v in pairs(defaultBaseGmodMap) do merged[k] = v end
	if cfg and type(cfg.baseGmodMap) == "table" then
		for k, v in pairs(cfg.baseGmodMap) do
			if type(k) == "string" and (v == true or v == false) then
				merged[k:lower()] = v
			end
		end
	end
	return merged
end

--- Detect the scripted class context based on URI
--- @param uri string
--- @return string? global, string? class
local function GetScopedClass(uri)
	-- Fix slashes
	local uriPath = uri:gsub("\\", "/")
	local normUri = uriPath:lower()

	-- Split path into segments (each slash)
	local segments = {}
	for seg in normUri:gmatch("[^/]+") do
		segments[#segments + 1] = seg
	end

	if #segments == 0 then return end

	-- Scope each folder into its relevant segments
	local scopes = {}
	for _, sc in ipairs(getScopes()) do
		local folder = (sc.folder or ""):gsub("\\", "/"):gsub("/+", "/"):lower()
		local folderSegs = {}
		for s in folder:gmatch("[^/]+") do
			folderSegs[#folderSegs + 1] = s
		end
		if #folderSegs > 0 then
			scopes[#scopes + 1] = { global = sc.global, segs = folderSegs }
		end
	end
	if #scopes == 0 then return end

	-- Find the nearest (from end) match of any scope folder sequence
	local best = nil -- {global=string, endIndex=integer, len=integer}
	for _, sc in ipairs(scopes) do
		local fsegs = sc.segs
		local flen = #fsegs
		-- start from (#segments - flen + 1) to include last valid position
		for i = #segments - flen + 1, 1, -1 do
			local match = true
			for j = 1, flen do
				if segments[i + j - 1] ~= fsegs[j] then
					match = false
					break
				end
			end
			if match then
				local endIndex = i + flen - 1
				if not best or endIndex > best.endIndex or (endIndex == best.endIndex and flen > best.len) then
					best = { global = sc.global, endIndex = endIndex, len = flen }
				end
				break -- Stop after first (nearest) match
			end
		end
	end

	if not best then return end

	-- Determine class by walking from the lua file backwards relative to the matched scope
	local afterIdx = best.endIndex + 1
	if afterIdx > #segments then return end

	local lastSeg = segments[#segments]
	local class
	if afterIdx == #segments then
		-- Single file directly under scope folder: <class>.lua
		class = lastSeg:gsub("%.lua$", "")
	else
		-- Any other nested file belongs to the first directory after the scope
		class = segments[afterIdx]
	end

	if class and class ~= "" then
		return best.global, class
	end
end

---@class diff
---@field start integer # The number of bytes at the beginning of the replacement
---@field finish integer # The number of bytes at the end of the replacement
---@field text string   # Replacement text

--- Insert localizations and preprocess text patches for GMod
--- @param uri string # File URI
--- @param text string # File content
--- @return diff[]|nil
function OnSetText(uri, text)
	---@type diff[]
	local diffs = {}

	-- Localize scripted table (ENT/SWEP/EFFECT/TOOL) uniquely per file and declare its class
	local global, class = GetScopedClass(uri)
	if global then
		-- If the file already declares a local <GLOBAL>, don't inject another one.
		local localPattern = "%f[%a]local%s+" .. global .. "%s*="
		local hasLocal = string.find(text, localPattern) ~= nil

		-- Prefer a folder-wide Base (shared.lua) when present
		local folderBase = findFolderBase(uri, global, class)
		local baseIdent, baseString
		if folderBase then
			if folderBase.kind == "ident" then
				baseIdent = folderBase.value
			else
				baseString = folderBase.value
			end
		else
			-- Detect <GLOBAL>.Base assignments in the current file. Prefer identifier (variable) matches
			baseIdent = text:match(global .. "%.%s*Base%s*=%s*([%a_][%w_%.]*)")
			baseString = text:match(global .. "%.%s*Base%s*=%s*[\"']([^\"']+)[\"']")
		end

		local parent = global
		local localText = ""
		if baseIdent then
			parent = baseIdent
			if not hasLocal then
				-- Use the identifier as the local table so the file refers to the base variable
				localText = ("local %s = %s\n\n"):format(global, baseIdent)
			end
		elseif baseString then
			-- If the base is a known GMod base class name, treat it as ENT
			local baseMap = getBaseGmodMap()
			if baseMap[baseString:lower()] then
				parent = global
			else
				parent = baseString
			end
			if not hasLocal then
				-- Can't reliably map a string base to a variable here; keep a fresh table
				localText = ("local %s = {}\n\n"):format(global)
			end
		else
			if not hasLocal then
				localText = ("local %s = {}\n\n"):format(global)
			end
		end

		if class then
			diffs[#diffs + 1] = {
				start = 1,
				finish = 0,
				text = ("---@class %s : %s\n%s"):format(class, parent, localText),
			}
		else
			if localText ~= "" then
				diffs[#diffs + 1] = {
					start = 1,
					finish = 0,
					text = localText,
				}
			end
		end
	end

	-- Replace DEFINE_BASECLASS preprocessor with a resolvable Lua form
	do
		local idx = 1
		while true do
			local s, e = string.find(text, "DEFINE_BASECLASS", idx, true)
			if not s then break end
			diffs[#diffs + 1] = {
				start = s,
				finish = e,
				text = "local BaseClass = baseclass.Get",
			}
			idx = e + 1
		end
	end

	if #diffs == 0 then
		return nil
	end
	return diffs
end

--- Bind NetworkVar/NetworkVarElement getters/setters to the class in AST
--- @param ast any
--- @param classNode any
--- @param source any
--- @param group table
--- @param isElement boolean
--- @return boolean|nil
local function BindNetworkVar(ast, classNode, source, group, isElement)
	local args = guide.getParams(source)
	if not args or #args < (isElement and 4 or 3) then
		return
	end

	-- Ensure call is on the same class (self)
	local argSelf = args[1]
	local targetSelf = guide.getSelfNode(argSelf)
	if not targetSelf then
		return
	end
	if targetSelf.node ~= classNode then
		-- auto generated function self after colon
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

	local dtMap = getDtTypes()
	local dtType = isElement and "number" or dtMap[argType[1]]
	local name = argName[1]
	if not dtType then
		return
	end

	local ok = helper.addDoc(ast, classNode, "field", ("Set%s fun(self: Entity, value: %s)"):format(name, dtType), group)
	if not ok then
		return false
	end
	ok = helper.addDoc(ast, classNode, "field", ("Get%s fun(self: Entity): %s"):format(name, dtType), group)
	if not ok then
		return false
	end
end

--- Transform AST to add class docs and NetworkVar bindings
--- @param uri string # File URI
--- @param ast any # File AST
--- @return any|nil
function OnTransformAst(uri, ast)
	local global, class = GetScopedClass(uri)
	if not global then
		return
	end

	-- First local statement should be the scripted global we injected above
	local function findClassNode(tbl, wanted)
		if type(tbl) ~= "table" then return nil end
		-- Try numeric sequence part first (1..#tbl)
		for i = 1, #tbl do
			local n = tbl[i]
			if n and n.type == "local" and guide.getKeyName(n) == wanted then
				return n
			end
		end

		-- Fallback: full table scan (covers string keys like "001", "002")
		for _, n in pairs(tbl) do
			if n and type(n) == "table" and n.type == "local" and guide.getKeyName(n) == wanted then
				return n
			end
		end

		return nil
	end

	local classNode = findClassNode(ast, global)
	if not classNode then
		return
	end

	local group = {}
	-- Ensure the class doc is attached to the AST
	local ok = helper.addClassDoc and helper.addClassDoc(ast, classNode, class .. ": " .. global, group)
	if not ok then
		-- If addClassDoc isn't available or failed, continue but abort if it explicitly returned false
		if ok == false then
			return
		end
	end

	-- Detect calls that occur inside SetupDataTables, even when wrapped in local helper functions
	local function isInsideSetupDataTables(node)
		local p = node
		for i = 1, 12 do
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
		-- Even if NetworkVar binding failed for some reason, don't break other features
		return
	end

	return ast
end

--- Custom require() resolver for GMod include patterns (.lua only)
--- @param uri string # The workspace or top-level URI
--- @param name string # Argument of require()
--- @return string[]|nil
function ResolveRequire(uri, name)
	if string.sub(name, -4) ~= ".lua" then
		return nil
	end

	-- See https://github.com/LuaLS/LuaLS.github.io/issues/48
	local _callingName, callingURI = debug.getlocal(5, 2)
	do
		assert(_callingName == "suri", "Something broke! Did LuaLS update?")
	end

	-- Directory of the calling file
	local callingDirURI = callingURI:match("^(.*)/[^/]*$")

	-- 1) Relative to the calling file
	local relative = callingDirURI .. "/" .. name
	if uriExists(relative) then
		return { relative }
	end

	-- 2) Relative to top-level lua/ directory
	local absolute = uri .. "/lua/" .. name
	return { absolute }
end
