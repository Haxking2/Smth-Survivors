local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local CS = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local binder = require(RS.Packages.binder)

local Entity = require(SSS.Entity)

local EntityManager = {}

EntityManager.Binder = binder.new({TagName = "Entity", Ancestors = {workspace}}, Entity)
EntityManager.Binder:Start()

function EntityManager.Damage(attacker, target, damage)
    print("stuff idkrn")
end

function EntityManager.SpawnEntity(entity)
    entity = ServerStorage.Entities:FindFirstChild("Noob"):Clone()
    CS:AddTag(entity.Humanoid, "Entity")
    entity.Parent = game.Workspace
end


return EntityManager