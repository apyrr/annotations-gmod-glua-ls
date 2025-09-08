-- Combined LuaLS plugin for Garry's Mod
-- Uses code from:
-- 1) https://github.com/TIMONz1535/glua-api-snippets/tree/plugin-wip1 (plugin.lua)
-- 2) https://github.com/CFC-Servers/luals_gmod_include (plugin.lua)
-- Features:
-- - Proper Include Paths
-- - Scripted Class Detection (ENT, SWEP, EFFECT, TOOL) with automated class annotation and inheritance
-- - NetworkVar getter/setter annotation
-- - AccessorFunc getter/setter annotation
-- - Derma Class Detection and automated annotation with inheritance
-- - Configurable via plugin.config.lua

local guide = require "parser.guide"
local helper = require "plugins.astHelper"
local fs = require("bee.filesystem")

local existsCache = {}

---@param uri string
---@return boolean
local function uriExists(uri)
	local cached = existsCache[uri]
	if cached ~= nil then
		return cached
	end
	local path = uri:sub(8)
	local exists = fs.exists(path)
	existsCache[uri] = exists
	return exists
end

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

-- Default scopes, can be overridden via plugin.config.lua, only here incase of missing config
local defaultScriptedScopes = {
	{ global = "ENT",    folder = "entities" },
	{ global = "SWEP",   folder = "weapons" },
	{ global = "EFFECT", folder = "effects" },
	{ global = "TOOL",   folder = "weapons/gmod_tool/stools" },
}

-- Load from plugin.config.lua
local pluginConfig --[[@type table|false|nil]]

---@return string|nil
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

---@return table|nil
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

---@return table
local function getScopes()
	local cfg = loadConfig()
	if cfg and type(cfg.scopes) == "table" then
		return cfg.scopes
	end
	return defaultScriptedScopes
end

-- Default NetworkVar type mapping, can be overridden via plugin.config.lua, only here incase of missing config
local defaultDtTypes = {
	String = "string",
	Bool   = "boolean",
	Float  = "number",
	Int    = "integer",
	Vector = "Vector",
	Angle  = "Angle",
	Entity = "Entity",
}

---@return table<string,string>
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

-- Default AccessorFunc FORCE_* mapping, can be overridden via plugin.config.lua
local defaultAccessorForceTypes = {
	FORCE_STRING = "string",
	FORCE_NUMBER = "number",
	FORCE_BOOL   = "boolean",
	FORCE_ANGLE  = "Angle",
	FORCE_COLOR  = "Color",
	FORCE_VECTOR = "Vector",
}

---@return table<string,string>
local function getAccessorForceTypes()
	local cfg = loadConfig()
	local merged = {}
	for k, v in pairs(defaultAccessorForceTypes) do merged[k] = v end
	if cfg and type(cfg.accessorForceTypes) == "table" then
		for k, v in pairs(cfg.accessorForceTypes) do
			if type(k) == "string" and type(v) == "string" and v ~= "" then
				merged[k] = v
			end
		end
	end
	return merged
end

---@return table<integer,string>
local function getAccessorForceTypesByNumber()
	local byName = getAccessorForceTypes()
	local order = {
		"FORCE_STRING", -- 1
		"FORCE_NUMBER", -- 2
		"FORCE_BOOL", -- 3
		"FORCE_ANGLE", -- 4
		"FORCE_COLOR", -- 5
		"FORCE_VECTOR", -- 6
	}
	local byNum = {}
	for i, key in ipairs(order) do
		byNum[i] = byName[key] or defaultAccessorForceTypes[key]
	end
	return byNum
end

-- Default entity bases, can be overridden via plugin.config.lua, only here incase of missing config
-- This is used to determine if we should inherit an entity from ENT instead of the literal string used for the base class
local defaultBaseGmodMap = {
	["base_gmodentity"] = true,
	["base_anim"] = true,
	["base_ai"] = true,
	["base_nextbot"] = true,
}

---@return table<string, boolean>
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

local folderBaseCache = {}

local function findFolderBase(uri, global, class)
	local callingDir = uri:match("^(.*)/[^/]*$")
	if not callingDir then
		return nil
	end
	local fileName = uri:match("[^/]+$") or ""
	fileName = fileName:lower()

	local commonHub = {
		["shared.lua"] = true,
		["init.lua"] = true,
		["cl_init.lua"] = true,
	}

	local folderPath
	if commonHub[fileName] then
		folderPath = callingDir
	else
		local parentName = callingDir:match("([^/]+)$")
		if parentName and parentName == class then
			folderPath = callingDir
		else
			return nil
		end
	end

	local cached = folderBaseCache[folderPath]
	if cached ~= nil then
		return cached
	end

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

	folderBaseCache[folderPath] = nil
	return nil
end


---@param text string
---@param className string
---@return boolean
local function hasExistingClassDocInText(text, className)
	local pattern = "---@class%s+" .. className .. "[%s: ]"
	return string.find(text, pattern) ~= nil
end

---@param text string
---@param className string
---@param beforePos integer
---@return boolean
local function hasClassDocBefore(text, className, beforePos)
	-- Check within a small window above the insertion point for an existing class doc
	local start = math.max(1, (beforePos or 1) - 800)
	local slice = text:sub(start, math.max(start, (beforePos or 1) - 1))
	local pattern = "---@class%s+" .. className .. "[%s: ]"
	return slice:find(pattern) ~= nil
end

---@param text string
---@return table[]
local function collectVguiRegisters(text)
	local registers = {}
	local pos = 1

	-- Collect vgui.Register calls
	while true do
		local s, e, className, varName, baseName = string.find(text,
			"vgui%s*%.%s*Register%s*%(%s*['\"]([^'\"]+)['\"]%s*,%s*([%a_][%w_]*)%s*,%s*['\"]([^'\"]+)['\"]%s*%)",
			pos)
		if not s then break end
		registers[#registers + 1] = {
			start = s,
			class = className,
			var = varName,
			base = baseName,
			type =
			"vgui.Register"
		}
		pos = e + 1
	end
	pos = 1
	while true do
		local s, e, className, varName = string.find(text,
			"vgui%s*%.%s*Register%s*%(%s*['\"]([^'\"]+)['\"]%s*,%s*([%a_][%w_]*)%s*%)",
			pos)
		if not s then break end
		registers[#registers + 1] = { start = s, class = className, var = varName, base = nil, type = "vgui.Register" }
		pos = e + 1
	end

	-- Collect derma.DefineControl calls
	pos = 1
	while true do
		local s, e, className, varName, baseName = string.find(text,
			"derma%s*%.%s*DefineControl%s*%(%s*['\"]([^'\"]+)['\"]%s*,%s*['\"][^'\"]*['\"]%s*,%s*([%a_][%w_]*)%s*,%s*['\"]([^'\"]+)['\"]%s*%)",
			pos)
		if not s then break end
		registers[#registers + 1] = {
			start = s,
			class = className,
			var = varName,
			base = baseName,
			type =
			"derma.DefineControl"
		}
		pos = e + 1
	end
	pos = 1
	while true do
		local s, e, className, varName = string.find(text,
			"derma%s*%.%s*DefineControl%s*%(%s*['\"]([^'\"]+)['\"]%s*,%s*['\"][^'\"]*['\"]%s*,%s*([%a_][%w_]*)%s*%)",
			pos)
		if not s then break end
		registers[#registers + 1] = {
			start = s,
			class = className,
			var = varName,
			base = nil,
			type =
			"derma.DefineControl"
		}
		pos = e + 1
	end

	return registers
end

---@param text string
---@return table<string, table[]>
local function collectVarTableAssignments(text)
	local assignsByVar = {}
	-- Match local variable assignments: local VAR = {}
	for s1, var1, e1 in string.gmatch(text, "()local%s+([%a_][%w_]*)%s*=%s*%b{}()") do
		local list = assignsByVar[var1] or {}
		list[#list + 1] = { s = s1, e = e1 - 1 }
		assignsByVar[var1] = list
	end
	-- Match global/non-local variable assignments: VAR = {}
	-- Use a simpler pattern that's more reliable
	local pos = 1
	while true do
		local s2, e2, var2 = string.find(text, "([%a_][%w_]*)%s*=%s*%b{}", pos)
		if not s2 then break end
		-- Check if this assignment is NOT preceded by "local" keyword
		local lineStart = text:sub(1, s2):match(".*\n()[^\n]*$") or 1
		local beforeAssign = text:sub(lineStart, s2 - 1)
		if not beforeAssign:match("local%s+$") then
			local list = assignsByVar[var2] or {}
			list[#list + 1] = { s = s2, e = e2 }
			assignsByVar[var2] = list
		end
		pos = e2 + 1
	end
	return assignsByVar
end

---@param assigns table[]|nil
---@param beforePos integer
---@return table|nil
local function findNearestPriorAssignment(assigns, beforePos)
	if not assigns then return nil end
	local best
	for _, a in ipairs(assigns) do
		if a.s < beforePos then
			if not best or a.s > best.s then
				best = a
			end
		end
	end
	return best
end

---@param text string
---@param global string|nil
---@param class string|nil
---@return table[]
local function collectAccessorFuncs(text, global, class)
	local accessorFuncs = {}
	local pos = 1
	while true do
		-- Look for AccessorFunc calls: AccessorFunc(table, varName, funcName, forceType?)
		local s, e, tableVar, varName, funcName, forceType = string.find(text,
			"AccessorFunc%s*%(%s*([%a_][%w_]*)%s*,%s*['\"]([^'\"]+)['\"]%s*,%s*['\"]([^'\"]+)['\"]%s*,%s*([%a_][%w_]*)%s*%)",
			pos)

		if s then
			accessorFuncs[#accessorFuncs + 1] = {
				start = s,
				tableVar = tableVar,
				varName = varName,
				funcName = funcName,
				forceType = forceType,
				targetClass = (tableVar == global) and class or nil
			}
			pos = e + 1
		else
			-- Try without forceType parameter
			s, e, tableVar, varName, funcName = string.find(text,
				"AccessorFunc%s*%(%s*([%a_][%w_]*)%s*,%s*['\"]([^'\"]+)['\"]%s*,%s*['\"]([^'\"]+)['\"]%s*%)", pos)
			if s then
				accessorFuncs[#accessorFuncs + 1] = {
					start = s,
					tableVar = tableVar,
					varName = varName,
					funcName = funcName,
					forceType = nil,
					targetClass = (tableVar == global) and class or nil
				}
				pos = e + 1
			else
				break
			end
		end
	end
	return accessorFuncs
end

---@param text string
---@return diff[]|nil
local function buildDermaClassDiffs(text)
	if not (text:find("vgui%s*%.%s*Register%s*%(") or text:find("derma%s*%.%s*DefineControl%s*%(")) then
		return nil
	end
	local registers = collectVguiRegisters(text)
	if #registers == 0 then return nil end
	local assignsByVar = collectVarTableAssignments(text)
	local accessorFuncs = collectAccessorFuncs(text, nil, nil)
	local diffs = {}
	local usedAssignSpan = {}
	-- Do not remove pre-existing @class docs; instead, skip inserting if one is already present nearby.

	for _, reg in ipairs(registers) do
		local className = reg.class
		local baseName = reg.base or "Panel"
		local best = findNearestPriorAssignment(assignsByVar[reg.var], reg.start)
		if best then
			local spanKey = tostring(best.s) .. ":" .. tostring(best.e)
			if not usedAssignSpan[spanKey] then
				local original = string.sub(text, best.s, best.e)

				-- If there's already a matching @class just above this assignment, skip to avoid duplicate
				if hasClassDocBefore(text, className, best.s) then
					usedAssignSpan[spanKey] = true
					goto continue_next_reg
				end

				-- Also skip if the class doc exists anywhere in the file, fixes some weird edge cases
				if hasExistingClassDocInText(text, className) then
					usedAssignSpan[spanKey] = true
					goto continue_next_reg
				end

				local nextAssignPos = math.huge
				for _, otherAssign in ipairs(assignsByVar[reg.var] or {}) do
					if otherAssign.s > best.e and otherAssign.s < nextAssignPos then
						nextAssignPos = otherAssign.s
					end
				end

				local fieldDocs = {}
				local accessorForceTypes = getAccessorForceTypes() or {
					FORCE_STRING = "string",
					FORCE_NUMBER = "number",
					FORCE_BOOL   = "boolean",
					FORCE_ANGLE  = "Angle",
					FORCE_COLOR  = "Color",
					FORCE_VECTOR = "Vector",
				}

				for _, accessor in ipairs(accessorFuncs) do
					if accessor.tableVar == reg.var and accessor.start > best.e and accessor.start < nextAssignPos then
						local forceType = "any"
						if accessor.forceType then
							forceType = accessorForceTypes[accessor.forceType] or "any"
						end

						fieldDocs[#fieldDocs + 1] = ("---@field Get%s fun(self: %s): %s"):format(accessor.funcName,
							className, forceType)
						fieldDocs[#fieldDocs + 1] = ("---@field Set%s fun(self: %s, value: %s)"):format(
							accessor.funcName, className, forceType)

						if accessor.varName then
							fieldDocs[#fieldDocs + 1] = ("---@field private %s %s"):format(accessor.varName, forceType)
						end
					end
				end

				local classDoc = ("---@class %s : %s"):format(className, baseName)
				if #fieldDocs > 0 then
					classDoc = classDoc .. "\n" .. table.concat(fieldDocs, "\n")
				end

				diffs[#diffs + 1] = {
					start = best.s,
					finish = best.e,
					text = classDoc .. "\n" .. original,
				}
				usedAssignSpan[spanKey] = true
			end
		end
		::continue_next_reg::
	end

	if #diffs == 0 then return nil end
	return diffs
end



---@param uri string
---@return string? global, string? class
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

---@param uri string # File URI
---@param text string # File content
---@return diff[]|nil
function OnSetText(uri, text)
	---@type diff[]
	local diffs = {}

	-- Handle scripted class (ENT/SWEP/EFFECT/TOOL) detection and localization
	local global, class = GetScopedClass(uri)
	if global then
		-- Check if this file also has Derma panel registrations to avoid conflicts
		local hasDermaRegistrations = (text:find("vgui%s*%.%s*Register%s*%(") or text:find("derma%s*%.%s*DefineControl%s*%(")) ~=
			nil

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
			baseIdent = text:match(global .. "%.%s*Base%s*=%s*([%a_][%w_%.]*)")
			baseString = text:match(global .. "%.%s*Base%s*=%s*[\"']([^\"']+)[\"']")
		end

		local parent = global
		local localText = ""
		if baseIdent then
			parent = baseIdent
			if not hasLocal then
				localText = ("local %s = %s\n\n"):format(global, baseIdent)
			end
		elseif baseString then
			local baseMap = getBaseGmodMap()
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
			local alreadyHasClassDoc = hasExistingClassDocInText(text, class)
			-- Only add scripted class annotation if there are no Derma registrations
			-- to avoid duplicate class annotations
			-- Collect AccessorFunc calls for this scripted class
			local accessorFuncs = alreadyHasClassDoc and {} or collectAccessorFuncs(text, global, class)
			local accessorForceTypes = getAccessorForceTypes() or {
				FORCE_STRING = "string",
				FORCE_NUMBER = "number",
				FORCE_BOOL   = "boolean",
				FORCE_ANGLE  = "Angle",
				FORCE_COLOR  = "Color",
				FORCE_VECTOR = "Vector",
			}

			local fieldDocs = {}
			for _, accessor in ipairs(accessorFuncs) do
				if accessor.targetClass then -- This AccessorFunc belongs to our scripted class
					local forceType = "any"
					if accessor.forceType then
						forceType = accessorForceTypes[accessor.forceType] or "any"
					end

					-- Add getter and setter field docs
					fieldDocs[#fieldDocs + 1] = ("---@field Get%s fun(self: %s): %s"):format(accessor.funcName, class,
						forceType)
					fieldDocs[#fieldDocs + 1] = ("---@field Set%s fun(self: %s, value: %s)"):format(accessor.funcName,
						class, forceType)

					-- Add private backing field if varName is provided
					if accessor.varName then
						fieldDocs[#fieldDocs + 1] = ("---@field private %s %s"):format(accessor.varName, forceType)
					end
				end
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
			elseif localText ~= "" then
				-- Class doc exists; only ensure local stub is present
				diffs[#diffs + 1] = {
					start = 1,
					finish = 0,
					text = localText,
				}
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
	end

	-- Handle DEFINE_BASECLASS replacement
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

	-- Handle Derma panels (vgui.Register)
	local panelDiffs = buildDermaClassDiffs(text)
	if panelDiffs then
		for _, d in ipairs(panelDiffs) do
			diffs[#diffs + 1] = d
		end
	end

	if #diffs == 0 then
		return nil
	end
	return diffs
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

	local dtMap = getDtTypes()
	local dtType = isElement and "number" or dtMap[argType[1]]
	local name = argName[1]
	if not dtType then
		return
	end

	return addGetSetDocs(ast, classNode, name, "Entity", dtType, group)
end


---@param ast any
---@param classNode any
---@param global string
---@param class string
---@param source any
---@param group table
---@return boolean|nil
local function BindAccessorFunc(ast, classNode, global, class, source, group)
	local args = guide.getParams(source)
	if not args or #args < 3 then
		return false
	end

	local argTab   = args[1]
	local argVar   = args[2]
	local argName  = args[3]
	local argForce = args[4]

	local function refersToClass(expr)
		if not expr then return false end
		if guide.getKeyName(expr) == global then
			return true
		end
		if expr.node == classNode then
			return true
		end
		local s = guide.getSelfNode(expr)
		if s and (s.node == classNode) then
			return true
		end
		if s then
			local ss = guide.getSelfNode(s)
			if ss and ss.node == classNode then
				return true
			end
		end
		return false
	end

	if not refersToClass(argTab) then
		return false
	end
	if not (argName and argName.type == "string") then
		return false
	end

	local forceType = "any"
	if argForce then
		local key = guide.getKeyName(argForce)
		if key then
			local map = getAccessorForceTypes()
			forceType = map[key] or forceType
		elseif argForce.type == "number" then
			local n = tonumber(argForce[1])
			if n then
				local numMap = getAccessorForceTypesByNumber()
				forceType = numMap[n] or forceType
			end
		end
	end

	local name = argName[1]
	if argVar and argVar.type == "string" then
		local varKey = argVar[1]
		helper.addDoc(ast, classNode, "field", ("private %s %s"):format(varKey, forceType), group)
	end
	local ok = addGetSetDocs(ast, classNode, name, class, forceType, group)
	if ok == false then
		return false
	end
	return true
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

---@param source any
---@return string|nil name, string|nil varKey, string forceType
local function parseAccessorFuncArgs(source)
	local args = guide.getParams(source)
	if not args or #args < 3 then
		return nil, nil, "any"
	end
	local argVar   = args[2]
	local argName  = args[3]
	local argForce = args[4]
	if not (argName and argName.type == "string") then
		return nil, nil, "any"
	end
	local forceType = "any"
	if argForce then
		local key = guide.getKeyName(argForce)
		if key then
			local map = getAccessorForceTypes()
			forceType = map[key] or forceType
		elseif argForce.type == "number" then
			local n = tonumber(argForce[1])
			if n then
				local numMap = getAccessorForceTypesByNumber()
				forceType = numMap[n] or forceType
			end
		end
	end
	local name = argName[1]
	local varKey
	if argVar and argVar.type == "string" then
		varKey = argVar[1]
	end
	return name, varKey, forceType
end

---@param ast any
---@param targetNode any
---@param selfType string
---@param name string
---@param varKey string|nil
---@param forceType string
---@param group table
local function applyAccessorFuncDocs(ast, targetNode, selfType, name, varKey, forceType, group)
	if varKey then
		helper.addDoc(ast, targetNode, "field", ("private %s %s"):format(varKey, forceType), group)
	end
	return addGetSetDocs(ast, targetNode, name, selfType, forceType, group)
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

---@param ast any
---@param expr any
---@return any|nil targetNode, string|nil name
local function resolveTargetNodeFromExpr(ast, expr)
	if not expr then return nil end
	if expr.node and type(expr.node) == "table" then
		return expr.node, guide.getKeyName(expr)
	end
	local key = guide.getKeyName(expr)
	if key then
		local n = findClassNode(ast, key)
		if n then return n, key end
	end
	return nil
end

---@param ast any
---@param classNode any|nil
---@param global string|nil
---@param class string|nil
---@param group table
local function processAccessorFuncs(ast, classNode, global, class, group, panelLookup)
	return guide.eachSourceType(ast, "call", function(source)
		local callee = source.node
		if guide.getKeyName(callee) ~= "AccessorFunc" then
			return
		end
		if classNode and global and class then
			local ok = BindAccessorFunc(ast, classNode, global, class, source, group)
			if ok ~= false then
				return ok
			end
		end
		local args = guide.getParams(source)
		if not args or not args[1] then return end
		local targetNode = resolveTargetNodeFromExpr(ast, args[1])
		if not targetNode then
			return
		end
		local sourceStart = source.start or 0
		local panelInfo
		if panelLookup then
			local entries = panelLookup[targetNode]
			if entries and #entries > 0 then
				local chosen
				for _, e in ipairs(entries) do
					if e.pos and e.pos >= sourceStart then
						chosen = e
						break
					end
				end
				panelInfo = chosen or entries[#entries]
			end
		end
		if not panelInfo then return end
		local name, varKey, forceType = parseAccessorFuncArgs(source)
		if not name then
			return
		end
		return applyAccessorFuncDocs(ast, targetNode, panelInfo.class, name, varKey, forceType, group)
	end)
end

---@param ast any
---@param group table
---@return table<any,{class:string, base:string|nil}>
local function processPanels(ast, group)
	local lookup = {}
	guide.eachSourceType(ast, "call", function(source)
		local callee = source.node
		local callName = guide.getKeyName(callee)

		-- Handle vgui.Register
		if callName == "Register" then
			local owner = callee.node and guide.getKeyName(callee.node)
			if owner ~= "vgui" then
				return
			end
			local args = guide.getParams(source)
			if not args or #args < 2 then return end
			local aName, aTable, aBase = args[1], args[2], args[3]
			if not (aName and aName.type == "string") then return end
			local className = aName[1]
			local baseName
			if aBase and aBase.type == "string" then
				baseName = aBase[1]
			end
			local targetNode = resolveTargetNodeFromExpr(ast, aTable)
			if not targetNode then return end
			local list = lookup[targetNode]
			if not list then
				list = {}
				lookup[targetNode] = list
			end
			list[#list + 1] = { class = className, base = baseName, pos = source.start or 0 }

			-- Handle derma.DefineControl
		elseif callName == "DefineControl" then
			local owner = callee.node and guide.getKeyName(callee.node)
			if owner ~= "derma" then
				return
			end
			local args = guide.getParams(source)
			if not args or #args < 3 then return end
			local aName, aDesc, aTable, aBase = args[1], args[2], args[3], args[4]
			if not (aName and aName.type == "string") then return end
			local className = aName[1]
			local baseName
			if aBase and aBase.type == "string" then
				baseName = aBase[1]
			end
			local targetNode = resolveTargetNodeFromExpr(ast, aTable)
			if not targetNode then return end
			local list = lookup[targetNode]
			if not list then
				list = {}
				lookup[targetNode] = list
			end
			list[#list + 1] = { class = className, base = baseName, pos = source.start or 0 }
		end
	end)
	return lookup
end

---@param uri string # File URI
---@param ast any # File AST
---@return any|nil
function OnTransformAst(uri, ast)
	local group = {}
	local classNode, global, class = processScriptedClass(uri, ast, group)
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
	if uriExists(relative) then
		return { relative }
	end

	local absolute = uri .. "/lua/" .. name
	return { absolute }
end
