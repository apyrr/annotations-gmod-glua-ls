---Returns if the passed object is a [function](https://wiki.facepunch.com/gmod/function).
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.isfunction
---@generic T
---@param variable T The variable to perform the type check for.
---@return TypeGuard<std.Extract<T, function>> # True if the variable is a function.
function _G.isfunction(variable) end
