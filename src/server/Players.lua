local CS = game:GetService("CollectionService")
local SSS = game:GetService("ServerScriptService")
local EntityManager = require(SSS.EntityManager)
local ItemManager = require(SSS.ItemManager)

local Players = {}

game.Players.PlayerAdded:Connect(function(player)
    Players[player] = {}
    local startingItems = {["Hyper Laser"] = 2}
    Players[player].ItemManager = ItemManager.new(startingItems)
    -- retrieve info from datastore, like starting items, upgrades etc.
    -- probably should turn this into a class, but not rn

    player.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 10)
        CS:AddTag(hum, "Entity")
        repeat
            task.wait()
        until EntityManager.Binder:Get(char.Humanoid)
        Players[player].Entity = EntityManager.Binder:Get(char.Humanoid)
        Players[player].Entity.AbilityManager:Update(Players[player].ItemManager.Items)

        char.Humanoid.Died:Connect(function()
            CS:RemoveTag(hum, "Entity")
        end)
    end)
end)

return Players