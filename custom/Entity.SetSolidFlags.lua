--- Custom override: SetSolidFlags accepts FSOLID enum or number since
--- bit.bor() with flag values returns a plain number.
---@realm shared
---@source https://wiki.facepunch.com/gmod/Entity:SetSolidFlags
---@param flags FSOLID|number
function Entity:SetSolidFlags(flags) end
