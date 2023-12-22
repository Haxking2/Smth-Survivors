local RS = game:GetService("ReplicatedStorage")
local Trove = require(RS.Packages.Trove)
local signal = require(RS.Packages.signal)

local Clock = {}
Clock.__index = Clock

function Clock.new(tickSpeed)
    local self = setmetatable({}, Clock)

    self._trove = Trove.new()
    self.Started = false
    self.Destroyed = false
    self.Active = true
    self.TickSpeed = tickSpeed
    self.Tick = self._trove:Add(signal.new(), "Destroy")

    return self
end

function Clock:Start()
    coroutine.wrap(function()
        if self.Started then return end
        self.Started = true
        self.Active = true
        while task.wait(self.TickSpeed) do
            if self.Active then
                self.Tick:Fire()
            end
            if self.Destroyed then
                break
            end
        end
    end)()

end

function Clock:Toggle()
    if self.Active then self.Active = false
    else self.Active = true
    end
end

function Clock:Destroy()
    self.Destroyed = true
    self._trove:Destroy()
    print("Destroying Clock")
end
return Clock