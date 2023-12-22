local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Trove = require(RS.Packages.Trove)

local Items = require(SSS.Items)


local ItemManager = {}
ItemManager.__index = ItemManager

function ItemManager.new(startingItems)
    local self = setmetatable({}, ItemManager)

    self._trove = Trove.new()
    self.Items = startingItems
    return self
end

function ItemManager:AddItem(item)
    if self.Items[item] then
        if self.Items[item] >= Items[item].MaxLevel then
            return
        else
            self.Items[item] += 1
        end
    else
        self.Items[item] = 1
    end
end

function ItemManager:Destroy()
    self._trove:Destroy()
    print("Destroying Item manager")
end

return ItemManager