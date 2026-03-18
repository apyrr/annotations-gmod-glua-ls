---Returns whether the passed object is a [VMatrix](https://wiki.facepunch.com/gmod/VMatrix).
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.ismatrix
---@generic T
---@param variable T The variable to perform the type check for.
---@return TypeGuard<std.Extract<T, VMatrix>> # True if the variable is a VMatrix.
function _G.ismatrix(variable) end
