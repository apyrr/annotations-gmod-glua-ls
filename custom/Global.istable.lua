---Returns if the passed object is a [table](https://wiki.facepunch.com/gmod/table).
--- 	**NOTE**: Will return TRUE for variables of type [Color](https://wiki.facepunch.com/gmod/Color)
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.istable
---@generic T
---@param variable T The variable to perform the type check for.
---@return TypeGuard<std.Extract<T, table>> # True if the variable is a table.
function _G.istable(variable) end
