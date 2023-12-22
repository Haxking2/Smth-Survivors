local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Trove = require(RS.Packages.Trove)
local Abilities = require(SSS.Abilities)
local AbilityManager = require(script.AbilityManager)

local Entity = {}
Entity.__index = Entity

function Entity.new(inst)
	if not inst:IsA("Humanoid") then return end
	local self = setmetatable({}, Entity)

	self._trove = Trove.new()
	self.Model = inst.Parent
	self.Name = inst.Parent.Name
	self.Team = 0
	self.Player = game.Players:GetPlayerFromCharacter(self.Model)
	self.Entity = self.Model:FindFirstChild("Entity")
	if self.Entity then
		self.Entity = self.Entity.Value
	end
	self.AbilityManager = self._trove:Add(AbilityManager.new(self.Player, self.Entity), "Destroy")

	print("Entity Constructed!" .. inst.Name)

	self.AbilityConn = self.AbilityManager.FireAbility:Connect(function(ability, props, stats)
		Abilities[ability].Activate(self.Model, props.Level, stats)
	end)

	return self
end

function Entity:Destroy()
	print("Entity Deconstructed!")
	self._trove:Destroy()
	self.AbilityConn = nil
end

return Entity