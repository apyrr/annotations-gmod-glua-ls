---Activates a given DSP (Digital Signal Processor) effect on all sounds that the player hears. This is equivalent to setting `dsp_player` convar on the player.
---@realm shared
---@source https://wiki.facepunch.com/gmod/Player:SetDSP
---@param dspEffectId number The index of the DSP sound filter to apply.
---@param fastReset? boolean If set to true the sound filter will be removed faster.
function Player:SetDSP(dspEffectId, fastReset) end
