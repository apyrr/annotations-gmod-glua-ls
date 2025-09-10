--[[
	Default values used throughout the plugin.
--]]

local Defaults = {}



-- Default scope configurations with integrated folder detection patterns
Defaults.scopes = {
	{
		global = "ENT",
		folder = "entities",
		folderIndicators = {
			"shared.lua",
			"init.lua",
			"cl_init.lua"
		},
		additionalPatterns = {
			"sv_.*%.lua$",
			"cl_.*%.lua$",
			"sh_.*%.lua$"
		}
	},
	{
		global = "SWEP",
		folder = "weapons",
		folderIndicators = {
			"shared.lua",
			"init.lua",
			"cl_init.lua"
		},
		additionalPatterns = {
			"sv_.*%.lua$",
			"cl_.*%.lua$",
			"sh_.*%.lua$"
		}
	},
	{
		global = "EFFECT",
		folder = "effects",
		folderIndicators = {
			"init.lua",
			"cl_init.lua"
		},
		additionalPatterns = {
			"cl_.*%.lua$"
		}
	},
	{
		global = "TOOL",
		folder = "weapons/gmod_tool/stools",
		folderIndicators = {
			"shared.lua",
			"init.lua",
			"cl_init.lua"
		},
		additionalPatterns = {
			"sv_.*%.lua$",
			"cl_.*%.lua$",
			"sh_.*%.lua$"
		}
	},
}

-- Default data type mappings for NetworkVar/NetworkVarElement
Defaults.dtTypes = {
	String = "string",
	Bool   = "boolean",
	Float  = "number",
	Int    = "integer",
	Vector = "Vector",
	Angle  = "Angle",
	Entity = "Entity",
}

-- Default base GMod entity mappings
Defaults.baseGmodMap = {
	["base_gmodentity"] = true,
	["base_anim"] = true,
	["base_ai"] = true,
	["base_nextbot"] = true,
}

-- Default AccessorFunc FORCE_* type mappings
Defaults.accessorForceTypes = {
	FORCE_STRING = "string",
	FORCE_NUMBER = "number",
	FORCE_BOOL   = "boolean",
	FORCE_ANGLE  = "Angle",
	FORCE_COLOR  = "Color",
	FORCE_VECTOR = "Vector",
}

-- Default AccessorFunc FORCE_* numeric mappings
Defaults.accessorForceTypesByNumber = {
	[0] = "any",  -- FORCE_NONE
	[1] = "string", -- FORCE_STRING
	[2] = "number", -- FORCE_NUMBER
	[3] = "boolean", -- FORCE_BOOL
	[4] = "Angle", -- FORCE_ANGLE
	[5] = "Color", -- FORCE_COLOR
	[6] = "Vector", -- FORCE_VECTOR
}



-- Default pattern matching configurations
Defaults.patterns = {
	-- VGUI registration patterns
	vguiRegister = "vgui%s*%.%s*Register%s*%(",
	dermaDefineControl = "derma%s*%.%s*DefineControl%s*%(",

	-- AccessorFunc patterns
	accessorFunc = "AccessorFunc%s*%(",

	-- NetworkVar patterns
	networkVar = "NetworkVar%s*%(",
	networkVarElement = "NetworkVarElement%s*%(",

	-- Variable assignment patterns
	variableAssignment = "([%a_][%w_]*)%s*=%s*",

	-- Class detection patterns
	localGlobal = "%f[%a]local%s+([%a_][%w_]*)%s*=",
	baseAssignment = "([%a_][%w_]*)%.%s*Base%s*=%s*([%a_][%w_%.]*)",
	baseStringAssignment = "([%a_][%w_]*)%.%s*Base%s*=%s*[\"']([^\"']+)[\"']"
}

return Defaults
