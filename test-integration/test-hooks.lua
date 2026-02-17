---@diagnostic disable: undefined-global
---@realm server

function GM:PlayerInitialSpawn(player, transition)
    print("Player spawned", player, transition)
end

hook.Add("PlayerInitialSpawn", "IntegrationTest.PlayerInitialSpawn", function(player)
    print(player:Nick())
end)

local createdEntity = ents.Create("prop_physics")
if createdEntity then
    createdEntity:SetPos(Vector(0, 0, 0))
end

local attack = IN_ATTACK
local jump = IN_JUMP
local pressedButtons = attack + jump

print(createdEntity, pressedButtons)
