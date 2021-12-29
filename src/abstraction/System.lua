local io = require("io")

local system = {}
system.__index = system

local function new()
    return setmetatable({}, system)
end

function system:print(value)
    io.write(tostring(value))
end

-- the module
return setmetatable(
    {
        new = new
    },
    {
        __call = function(_, ...)
            return new()
        end
    }
)