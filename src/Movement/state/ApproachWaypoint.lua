local construct = require("abstraction/Construct")()
local brakes = require("Brakes")()
local diag = require("Diagnostics")()
local calc = require("Calc")
local nullVec = require("cpml/vec3")()
local brakes = require("Brakes")()

local name = "ApproachWaypoint"
local _1kph = calc.Kph2Mps(1)

local state = {}
state.__index = state

local function new(fsm)
    diag:AssertIsTable(fsm, "fsm", name .. ":new")

    local o = {
        fsm = fsm
    }

    setmetatable(o, state)

    return o
end

function state:Enter()
end

function state:Leave()

end

function state:Flush(next, previous, rabbit)
    local currentPos = construct.position.Current()
    local brakeDistance, brakeAccelerationNeeded = brakes:BrakeDistance(next:DistanceTo())
    local velocity = construct.velocity:Movement()
    local travelDir = velocity:normalize()

    local dirToRabbit = (rabbit - currentPos):normalize()
    local outOfAlignment = travelDir:dot(dirToRabbit) < 0.8

    local needToBrake = (brakeDistance > 0 and brakeDistance >= next:DistanceTo()) or brakeAccelerationNeeded > 0

    brakes:Set(needToBrake or outOfAlignment)

    local acc = nullVec
    if brakeAccelerationNeeded > 0 then
        acc = brakeAccelerationNeeded * -travelDir
    end

    acc = acc + (dirToRabbit + next:DirectionTo()):normalize()

    self.fsm:Thrust(acc)
end

function state:Update()
end

function state:WaypointReached(isLastWaypoint, next, previous)
    if isLastWaypoint then
        self.fsm:SetState(Hold(self.fsm))
    else
        self.fsm:SetState(Travel(self.fsm))
    end
end

function state:Name()
    return name
end

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