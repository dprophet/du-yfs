local vec3 = require("builtin/vec3")
local Pid = require("builtin/pid")
local library = require("abstraction/Library")()

local stab = {}
stab.__index = stab

---Creates a new Stabilizer that alignes the construct to a reference direction
---@param core Core The core
---@param flightcore FlightCore The FlightCore
---@return table Stabilizer The new Stabilizer
local function new(flightcore)
    local instance = {
        core = library.getCoreUnit(),
        controller = library.getController(),
        flightCore = flightcore,
        enabled = false,
        pidX = Pid(0, 0.01, 70),
        pidY = Pid(0, 0.01, 70),
        pidZ = Pid(0, 0.01, 70),
        baseAngularRotationAcceleration = 2 * math.pi, -- One turn per second.
        -- Shall return the reference vector and vector to adjust towards reference.
        getVectors = nil,
        turnTowards = nil
    }

    setmetatable(instance, stab)
    return instance
end

function stab:Enable()
    self.enabled = true
end

function stab:Disable()
    self.enabled = false
    self.turnTowards = nil
end

function stab:StablilizeUpward()
    self.getVectors = function()
        local core = self.core
        return -vec3(core.getWorldVertical()), vec3(core.getConstructWorldUp())
    end

    self:Enable()
end

function stab:TurnTowards(direction)
    self.turnTowards = direction
end

---Stabilizes the construct based on the two vectors returned by the getVectors member function
function stab:Stabilize()
    if self.enabled and self.getVectors ~= nil then
        local ref, toAdjust = self:getVectors()

        local adjustCross = toAdjust:cross(ref)

        if self.turnTowards ~= nil then
            local towardsCross = vec3(self.core.getConstructWorldForward()):cross(self.turnTowards)
            adjustCross = adjustCross + towardsCross
        end

        self.pidX:inject(adjustCross.x)
        self.pidY:inject(adjustCross.y)
        self.pidZ:inject(adjustCross.z)

        local angularAcceleration = self.baseAngularRotationAcceleration * vec3(self.pidX:get(), self.pidY:get(), self.pidZ:get())
        self.flightCore:SetRotation(angularAcceleration)
    end
end

-- The module
return setmetatable(
    {
        new = new
    },
    {
        __call = function(_, ...)
            return new(...)
        end
    }
)
