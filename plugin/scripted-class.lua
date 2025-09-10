--[[
	Scripted class detection and path/scope logic.

	Handles detection of Garry's Mod scripted classes (ENT, SWEP, EFFECT, TOOL) based on
	file paths and folder structures. Provides utilities for determining class names,
	global scopes, and base class inheritance from file system organization.
--]]

local ScriptedClass = {}

-- Class Detection Utilities Module
local ClassDetection = {}

---Normalises a URI path and splits it into segments
---@param uri string
---@return string[] segments
function ClassDetection.parseUriPath(uri)
	local uriPath = uri:gsub("\\", "/")
	local normUri = uriPath:lower()

	local segments = {}
	for seg in normUri:gmatch("[^/]+") do
		segments[#segments + 1] = seg
	end

	return segments
end

---Converts scope configurations into searchable format
---@param scopes table[] Scope configurations
---@return table[] scopes
function ClassDetection.prepareScopes(scopes)
	local preparedScopes = {}
	for _, sc in ipairs(scopes) do
		local folder = (sc.folder or ""):gsub("\\", "/"):gsub("/+", "/"):lower()
		local folderSegs = {}
		for s in folder:gmatch("[^/]+") do
			folderSegs[#folderSegs + 1] = s
		end
		if #folderSegs > 0 then
			preparedScopes[#preparedScopes + 1] = { global = sc.global, segs = folderSegs }
		end
	end
	return preparedScopes
end

---Finds the best matching scope for the given path segments
---@param segments string[]
---@param scopes table[]
---@return table|nil best
function ClassDetection.findBestScope(segments, scopes)
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

	return best
end

---Determines the class name from path segments and scope match
---@param segments string[]
---@param best table
---@return string|nil class
function ClassDetection.determineClassName(segments, best)
	local afterIdx = best.endIndex + 1
	if afterIdx > #segments then return nil end

	local lastSeg = segments[#segments]
	local class
	if afterIdx == #segments then
		-- Single file directly under scope folder: <class>.lua
		class = lastSeg:gsub("%.lua$", "")
	else
		-- Any other nested file belongs to the first directory after the scope
		class = segments[afterIdx]
	end

	return (class and class ~= "") and class or nil
end

---Detects scripted class global and class name from URI
---@param uri string File URI
---@param scopes table[] Scope configurations
---@return string? global, string? class
function ScriptedClass.getScopedClass(uri, scopes)
	local segments = ClassDetection.parseUriPath(uri)
	if #segments == 0 then return end

	local preparedScopes = ClassDetection.prepareScopes(scopes)
	if #preparedScopes == 0 then return end

	local best = ClassDetection.findBestScope(segments, preparedScopes)
	if not best then return end

	local class = ClassDetection.determineClassName(segments, best)
	if class then
		return best.global, class
	end
end

return ScriptedClass
