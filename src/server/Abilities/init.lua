local Abilities = {}

for _, ability in pairs(script:GetChildren()) do
    if ability:IsA("ModuleScript") then
        Abilities[ability.Name] = require(ability)
    end
end

return Abilities