-- Configuration for glua-api-snippets LuaLS plugin
-- Rename or copy this file to adjust scope detection without editing plugin.lua.
-- Scopes define a global table name and a folder path segment to match anywhere in the file URI.
-- The class is inferred as the next path segment after the folder.
-- Examples:
--   { global = "ENT", folder = "entities" }
--   { global = "SWEP", folder = "weapons" }
--   { global = "TOOL", folder = "weapons/gmod_tool/stools" }

return {
	-- Configure scripted scopes here. Order matters if folders can overlap; the first match wins.
	scopes = {
		{ global = "ENT",    folder = "entities" },
		{ global = "SWEP",   folder = "weapons" },
		{ global = "EFFECT", folder = "effects" },
		{ global = "TOOL",   folder = "weapons/gmod_tool/stools" },
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

	-- Map of known GMod base entity names that should be treated as "ENT" parents
	-- If an ENT.Base is a string and matches one of these keys, we then inherit from `ENT` instead of the string
	baseGmodMap = {
		["base_gmodentity"] = true,
		["base_anim"] = true,
		["base_ai"] = true,
		["base_nextbot"] = true,
	},

	-- Optional: override AccessorFunc FORCE_* mappings used to type Set*/Get*
	-- Keys are FORCE_* enum names; values are LuaLS types
	accessorForceTypes = {
		FORCE_STRING = "string",
		FORCE_NUMBER = "number",
		FORCE_BOOL   = "boolean",
		FORCE_ANGLE  = "Angle",
		FORCE_COLOR  = "Color",
		FORCE_VECTOR = "Vector",
	},
}
