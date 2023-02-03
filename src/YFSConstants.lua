local Vec3 = require("math/Vec3")

local constants = {
    ticksPerSecond = 60.0,
    flushTick = 1 / 60.0,
    universe = {
        up = Vec3.New(0, 1, 0),
        forward = Vec3.New(1, 0, 0),
        right = Vec3.New(0, 0, 1)
    },
    direction = {
        counterClockwise = 1,
        clockwise = -1,
        rightOf = 1,
        leftOf = -1,
        still = 0
    },
    flight = {
        speedPid = {
            p = 0.02,
            i = 0.005,
            d = 100,
            a = 0.99
        }
    }

}

return constants
