---Returns if the passed object is a [string](https://wiki.facepunch.com/gmod/string).
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.isstring
---@generic T
---@param variable T The variable to perform the type check for.
---@return TypeGuard<std.Extract<T, string>> # True if the variable is a string.
function _G.isstring(variable) end
