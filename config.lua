return {
	-- Configure scripted scopes here. Order matters if folders can overlap; the first match wins.
	-- Each scope includes folder detection patterns for determining single-file vs folder-based structures
	scopes = {
		{               -- Entities within /entities folder, scope ENT
			global = "ENT", -- This is the scope that the class will inherit from
			folder = "entities", -- This is the folder we'll match against
			folderIndicators = { -- We look for these files to dermine if this is a single-file class or a folder-based class
				"shared.lua",
				"init.lua",
				"cl_init.lua"
			},
			additionalPatterns = { -- These patterns are additionally used to help determine if this is a single-file class or a folder-based class
				"sv_.*%.lua$",
				"cl_.*%.lua$",
				"sh_.*%.lua$"
			}
		},
		{ -- Weapons within /weapons folder, scope SWEP
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
		{ -- Effects within /effects folder, scope EFFECT
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
		{ -- Tools within /weapons/gmod_tool/stools folder, scope TOOL
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

	-- Common parameter name to type hints used by VM.OnCompileFunctionParam
	-- These are used to "guess" parameter types, only if no other type info is available
	-- I'm not really sure how I feel about this, needs more testing to ensure it doesn't break things
	paramNameTypes = {

		-- player
		ply = "Player",
		player = "Player",
		client = "Player",

		-- entity
		ent = "Entity",
		entity = "Entity",
		veh = "Vehicle",
		car = "Vehicle",

		-- vectors / angles / colors
		vec = "Vector",
		vector = "Vector",
		ang = "Angle",
		angle = "Angle",
		col = "Color",
		color = "Color",
		pos = "Vector",
		pos1 = "Vector",
		pos2 = "Vector",
		startpos = "Vector",
		endpos = "Vector",
		plypos = "Vector",
		hitpos = "Vector",

		-- ent related, not sure about these ones
		owner = "Entity",
		attacker = "Entity",
		victim = "Entity",
		activator = "Entity",
		caller = "Entity",
		inflictor = "Entity",
		swep = "SWEP",
		wep = "Weapon",
		weapon = "Weapon",

		-- strings
		name = "string",
		filepath = "string",
		filename = "string",
		url = "string",
		steamid = "string",
		steamid64 = "string",
		sid64 = "string",
		str = "string",

		-- generic
		tbl = "table",
		msg = "string",
		distance = "number",
		speed = "number",
		num = "number",
		count = "number",

	},

	-- Numeric FORCE_* mapping (optional but recommended)
	-- Keys correspond to FORCE_* numeric constants used by AccessorFunc when a number is passed
	accessorForceTypesByNumber = {
		[0] = "any", -- FORCE_NONE
		[1] = "string", -- FORCE_STRING
		[2] = "number", -- FORCE_NUMBER
		[3] = "boolean", -- FORCE_BOOL
		[4] = "Angle", -- FORCE_ANGLE
		[5] = "Color", -- FORCE_COLOR
		[6] = "Vector", -- FORCE_VECTOR
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

		-- DEFINE_BASECLASS pattern
		defineBaseclass = "DEFINE_BASECLASS%s*(%b())",

		-- Variable assignment patterns
		variableAssignment = "([%a_][%w_]*)%s*=%s*",

		-- Class detection patterns
		localGlobal = "%f[%a]local%s+([%a_][%w_]*)%s*=",

		-- Pattern for a specific name, we replace {name} with the identifier
		localGlobalByNameTemplate = "%f[%a]local%s+{name}%s*=",

		baseAssignment = "([%a_][%w_]*)%.%s*Base%s*=%s*([%a_][%w_%.]*)",
		baseStringAssignment = "([%a_][%w_]*)%.%s*Base%s*=%s*[\"']([^\"']+)[\"']",

		-- Pattern for specific base, we replace {name} with the identifier
		baseAssignmentByNameTemplate = "{name}%.%s*Base%s*=%s*([%a_][%w_%.]*)",
		baseStringAssignmentByNameTemplate = "{name}%.%s*Base%s*=%s*[\"']([^\"']+)[\"']",
	}
}
