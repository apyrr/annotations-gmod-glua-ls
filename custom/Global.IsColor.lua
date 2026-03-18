---Returns whether the given object does or doesn't have a `metatable` of a color.
---@realm shared
---@realm menu
---@source https://wiki.facepunch.com/gmod/Global.IsColor
---@generic T
---@param Object T The object to be tested
---@return TypeGuard<std.Extract<T, Color>> # Whether the given object is a color or not
function _G.IsColor(Object) end
