local brakes = require("flight/Brakes")()
local checks = require("du-libs:debug/Checks")
require("flight/state/Require")

local state = {}
state.__index = state

local name = "Hold"

local function new(fsm)
    checks.IsTable(fsm, "fsm", name .. ":new")

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

function state:Flush(next, previous, chaseData)
    if next:Reached() then
        brakes:Set(true)
        self.fsm:Thrust() -- Just counter gravity
    else
        self.fsm:SetState(ApproachWaypoint(self.fsm))
    end
end

function state:Update()
end

function state:WaypointReached(isLastWaypoint, next, previous)
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