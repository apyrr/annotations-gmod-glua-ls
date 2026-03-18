---Returns if the passed object is a [boolean](https://wiki.facepunch.com/gmod/boolean).
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.isbool
---@generic T
---@param variable T The variable to perform the type check for.
---@return TypeGuard<std.Extract<T, boolean>> # True if the variable is a boolean.
function _G.isbool(variable) end
