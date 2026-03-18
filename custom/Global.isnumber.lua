---Returns if the passed object is a [number](https://wiki.facepunch.com/gmod/number).
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.isnumber
---@generic T
---@param variable T The variable to perform the type check for.
---@return TypeGuard<std.Extract<T, number>> # True if the variable is a number.
function _G.isnumber(variable) end
