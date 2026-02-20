---Retrieves a vector previously stored using [Tool:SetObject](https://wiki.facepunch.com/gmod/Tool:SetObject). See also [Tool:GetLocalPos](https://wiki.facepunch.com/gmod/Tool:GetLocalPos).
---@realm shared
---@source https://wiki.facepunch.com/gmod/Tool:GetPos
---@param id? number The id of the object which was set in Tool:SetObject.
---@return Vector # Associated vector with given id. The vector is converted from Tool:GetLocalPos.
function Tool:GetPos(id) end
