---Returns if the passed object is an [Angle](https://wiki.facepunch.com/gmod/Angle).
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.isangle
---@generic T
---@param variable T The variable to perform the type check for.
---@return TypeGuard<std.Extract<T, Angle>> # True if the variable is an Angle.
function _G.isangle(variable) end
