---Returns if the passed object is an [Entity](https://wiki.facepunch.com/gmod/Entity).
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.IsEntity
---@generic T
---@param variable T The variable to check.
---@return TypeGuard<std.Extract<T, Entity>> # True if the variable is an Entity.
function _G.isentity(variable) end
