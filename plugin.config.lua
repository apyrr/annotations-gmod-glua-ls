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
}
