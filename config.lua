return {
	-- Configure scripted scopes here. Order matters if folders can overlap; the first match wins.
	-- Each scope includes folder detection patterns for determining single-file vs folder-based structures
	scopes = {
		{
			global = "ENT",
			folder = "entities",
			-- Folder detection patterns for entities
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
			-- Folder detection patterns for weapons
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
			-- Folder detection patterns for effects
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
			-- Folder detection patterns for tools
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
	},

	-- Configure datatable type mappings for NetworkVar/NetworkVarElement
	-- Keys are GMod DT type names; values are LuaLS types.
	dtTypes = {
		String = "string",
		Bool   = "boolean",
		Float  = "number",
		Int    = "integer",
		Vector = "Vector",
		Angle  = "Angle",
		Entity = "Entity",
	},

	-- Known GMod base entity names that should be treated as "ENT" parents
	-- If an ENT.Base is a string and matches one of these keys, we inherit from `ENT` instead of the string
	baseGmodMap = {
		["base_gmodentity"] = true,
		["base_anim"] = true,
		["base_ai"] = true,
		["base_nextbot"] = true,
	},

	-- AccessorFunc FORCE_* mappings used to type Set*/Get*
	-- Keys are FORCE_* enum names, values are LuaLS types
	accessorForceTypes = {
		FORCE_STRING = "string",
		FORCE_NUMBER = "number",
		FORCE_BOOL   = "boolean",
		FORCE_ANGLE  = "Angle",
		FORCE_COLOR  = "Color",
		FORCE_VECTOR = "Vector",
	},

	-- Pattern matching
	patterns = {
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
}
