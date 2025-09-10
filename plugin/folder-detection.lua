--[[
	Handles the detection of whether a class is defined in a single file or across multiple files in a folder.
--]]

local FolderDetection = {}

---Checks if a file exists (mock implementation for LuaLS environment)
---@param path string
---@return boolean
local function fileExists(path)
	return true -- TODO: Try see if this can be fixed, was changed to always be true due to weird bugs
end

---Gets the directory listing (mock implementation for LuaLS environment)
---@param dir string
---@return string[]
local function getDirectoryListing(dir)
	return {} -- TODO: Try see if this can be fixed, was changed to always be true due to weird bugs
end

---Checks if any files in a directory match the given patterns
---@param dir string
---@param patterns string[]
---@return boolean
local function hasMatchingFiles(dir, patterns)
	local files = getDirectoryListing(dir)

	for _, file in ipairs(files) do
		local fileName = file:lower()
		for _, pattern in ipairs(patterns) do
			if fileName:match(pattern) then
				return true
			end
		end
	end

	return false
end

---Determines if a class should be applied to an entire folder based on detection patterns
---@param uri string File URI
---@param global string Global scope (ENT, SWEP, etc.)
---@param class string Class name
---@param config table Configuration with scopes containing folderIndicators and additionalPatterns
---@return table|nil folderInfo Information about folder detection
function FolderDetection.detectFolderStructure(uri, global, class, config)
	local callingDir = uri:match("^(.*)/[^/]*$")
	if not callingDir then
		return nil
	end

	local fileName = uri:match("[^/]+$") or ""
	fileName = fileName:lower()

	-- Get detection patterns for this scope type from scopes configuration
	local detectionConfig = nil
	if config.scopes then
		for _, scope in ipairs(config.scopes) do
			if scope.global == global then
				detectionConfig = scope
				break
			end
		end
	end

	if not detectionConfig or not detectionConfig.folderIndicators then
		-- Fallback to basic detection if no config available
		return FolderDetection.basicFolderDetection(uri, global, class)
	end

	local folderIndicators = detectionConfig.folderIndicators or {}
	local additionalPatterns = detectionConfig.additionalPatterns or {}

	-- Check if current file is a folder indicator
	local isCurrentFileFolderIndicator = false
	for _, indicator in ipairs(folderIndicators) do
		if fileName == indicator then
			isCurrentFileFolderIndicator = true
			break
		end
	end

	local folderPath

	if isCurrentFileFolderIndicator then
		-- File is a folder indicator (like init.lua), apply to entire directory
		folderPath = callingDir
	else
		-- Check if we're in a class-named directory
		local parentName = callingDir:match("([^/]+)$")
		if parentName and parentName == class then
			-- We're in a directory named after the class
			-- Check if there are other files that suggest this is a folder-based structure
			if hasMatchingFiles(callingDir, folderIndicators) or
				hasMatchingFiles(callingDir, additionalPatterns) then
				folderPath = callingDir
			end
		end
	end

	if not folderPath then
		return nil
	end

	-- Determine base class information
	local baseInfo = FolderDetection.extractBaseFromFolder(folderPath, global)

	return {
		path = folderPath,
		kind = baseInfo and baseInfo.kind or "string",
		value = baseInfo and baseInfo.value or global
	}
end

---Basic folder detection fallback for when no configuration is available
---@param uri string
---@param global string
---@param class string
---@return table|nil
function FolderDetection.basicFolderDetection(uri, global, class)
	local callingDir = uri:match("^(.*)/[^/]*$")
	if not callingDir then
		return nil
	end

	local fileName = uri:match("[^/]+$") or ""
	fileName = fileName:lower()

	-- Basic folder indicators
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
		end
	end

	if not folderPath then
		return nil
	end

	return {
		path = folderPath,
		kind = "string",
		value = global
	}
end

---Extracts base class information from folder structure
---@param folderPath string
---@param global string
---@return table|nil baseInfo
function FolderDetection.extractBaseFromFolder(folderPath, global)
	-- Try to read a base file or configuration
	-- This is a simplified implementation
	local basePath = folderPath .. "/base.txt"

	if fileExists(basePath) then
		-- In a real implementation, read the base class from file
		return {
			kind = "ident",
			value = global -- Fallback to global
		}
	end

	return {
		kind = "string",
		value = global
	}
end

---Checks if a directory contains files that match folder-based patterns
---@param dir string Directory path
---@param global string Global scope type
---@param config table Configuration
---@return boolean
function FolderDetection.isFolderBasedStructure(dir, global, config)
	-- Get detection patterns for this scope type from scopes configuration
	local detectionConfig = nil
	if config.scopes then
		for _, scope in ipairs(config.scopes) do
			if scope.global == global then
				detectionConfig = scope
				break
			end
		end
	end

	if not detectionConfig or not detectionConfig.folderIndicators then
		return false
	end

	local folderIndicators = detectionConfig.folderIndicators or {}
	local additionalPatterns = detectionConfig.additionalPatterns or {}

	-- Check for folder indicators
	if hasMatchingFiles(dir, folderIndicators) then
		return true
	end

	-- Check for additional patterns
	if hasMatchingFiles(dir, additionalPatterns) then
		return true
	end

	return false
end

return FolderDetection
