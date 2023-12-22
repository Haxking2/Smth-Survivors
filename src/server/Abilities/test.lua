local test = {}

function test.Activate(Entity, AbilityLevel, Stats)
    print("test ability activated!" .. AbilityLevel)
    Entity.Humanoid.Health -= Stats.Damage*AbilityLevel
end

return test