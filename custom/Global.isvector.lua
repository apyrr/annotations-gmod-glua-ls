---Returns if the passed object is a [Vector](https://wiki.facepunch.com/gmod/Vector).
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.isvector
---@generic T
---@param variable T The variable to perform the type check for.
---@return TypeGuard<std.Extract<T, Vector>> # True if the variable is a Vector.
function _G.isvector(variable) end
