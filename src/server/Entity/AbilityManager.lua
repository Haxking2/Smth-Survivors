-- redo this a bit
-- maybe make a separate class for stats (not necessary tho)
-- make an ItemManager Class for players and possibly also make a PlayerEntity Class

-- also add manual/automatic activation options for abilities

local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Trove = require(RS.Packages.Trove)
local Clock = require(SSS.Clock)
local signal = require(RS.Packages.signal)

local Items = require(SSS.Items)
local Entities = require(ServerStorage.Entities.Entities)

local BASE = {
    Health = 100,
    Damage = 5
}

local AbilityManager = {}
AbilityManager.__index = AbilityManager

function AbilityManager.new(Player, EntityType)
    local self = setmetatable({}, AbilityManager)

    self._trove = Trove.new()
    self.Stats = BASE
    self.Abilities = {}
    -- make something for temporary stat boosts
    self.Clock = self._trove:Add(Clock.new(1), "Destroy")
    self.FireAbility = self._trove:Add(signal.new(), "Destroy")
    self.TickConn = self.Clock.Tick:Connect(function()
        self:ClockTick()
    end)

    self.Clock:Start()

    if Player then
        self.Player = Player
        self.Type = "Player"
    else
        self.Type = "NPC"
        self.EntityType = EntityType
        self.Stats = Entities[EntityType].Stats
        self.Abilities = Entities[EntityType].Abilities
    end
    return self
end

function AbilityManager:ClockTick()
    for ability, props in pairs(self.Abilities) do
        self.Abilities[ability].TicksUntilActivation -= 1
        if self.Abilities[ability].TicksUntilActivation <= 0 and self.Abilities[ability].ActivationType == "Automatic" then
            self.FireAbility:Fire(ability, props, self.Stats)
            self.Abilities[ability].TicksUntilActivation = props.Cooldown
        elseif self.Abilities[ability].TicksUntilActivation <= 0 then
            self.Abilities[ability].TicksUntilActivation = 0
        end
    end
end

function AbilityManager:Update(items)
    print(items)
    local Stats = BASE
    local Abilities = {}
    for item, level in pairs(items) do
        for stat, value in pairs(Items[item].StatBoosts) do
            Stats[stat] += value
        end
        if self.Abilities[Items[item].Ability] then
            Abilities[Items[item].Ability]= self.Abilities[Items[item].Ability]
            Abilities[Items[item].Ability].Level = level
        else
            Abilities[Items[item].Ability] = {Level = level, Cooldown = Items[item].Cooldown, TicksUntilActivation = Items[item].Cooldown, ActivationType = "Automatic"}
        end
    end
    self.Stats = Stats
    self.Abilities = Abilities
    -- could correspond an item to ability for ui stuff?
end

function AbilityManager:Destroy()
    self._trove:Destroy()
    self.TickConn = nil
    print("Destroying ability manager")
end

return AbilityManager