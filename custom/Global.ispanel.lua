---Returns if the passed object is a [Panel](https://wiki.facepunch.com/gmod/Panel).
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.ispanel
---@generic T
---@param variable T The variable to perform the type check for.
---@return TypeGuard<std.Extract<T, Panel>> # True if the variable is a Panel.
function _G.ispanel(variable) end
