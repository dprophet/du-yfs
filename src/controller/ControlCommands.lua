---@module "commandline/CommandLine"
---@module "input/Input"

local Criteria     = require("input/Criteria")
local PointOptions = require("flight/route/PointOptions")
local log          = require("debug/Log")()
local vehicle      = require("abstraction/Vehicle").New()
local brakes       = require("flight/Brakes").Instance()
local calc         = require("util/Calc")
local universe     = require("universe/Universe").Instance()
local keys         = require("input/Keys")
local Clamp        = calc.Clamp

---@class ControlCommands
---@field New fun(input:Input, cmd:Command, flightCore:FlightCore)

local ControlCommands = {}
ControlCommands.__index = ControlCommands

---Creates a new RouteModeController
---@param input Input
---@param cmd CommandLine
---@param flightCore FlightCore
---@return ControlCommands
function ControlCommands.New(input, cmd, flightCore)
    local s = {}

    local movestep = 0.1
    local turnAngle = 1
    local speed = construct.getMaxSpeed()
    local rc = flightCore.GetRouteController()

    local function lockUser()
        if player.isFrozen() == 1 then
            player.freeze(false)
            log:Info("Player released")
        else
            player.freeze(true)
            log:Info("Player locked")
        end
    end

    -- shift + alt + Option9 to switch modes
    input.Register(keys.option9, Criteria.New().LAlt().LShift().OnPress(), lockUser)

    -- Setup brakes
    input.Register(keys.brake, Criteria.New().OnPress(), function() brakes:Forced(true) end)
    input.Register(keys.brake, Criteria.New().OnRelease(), function() brakes:Forced(false) end)

    cmd.Accept("idle", function(data)
        log:Info("Going idle!")
        flightCore.GoIdle()
    end)

    cmd.Accept("hold", function(data)
        local r = rc.ActivateTempRoute().AddCurrentPos()
        flightCore.StartFlight()
    end)

    ---@param c Command
    local function addPointOptions(c)
        c.Option("-precision").AsBoolean().Default(false)
        c.Option("-lockdir").AsBoolean().Default(false)
        c.Option("-maxspeed").AsNumber().Default(0)
        c.Option("-margin").AsNumber().Default(0.1)
    end

    ---@param data table
    ---@return PointOptions
    local function createOptions(data)
        local opt = PointOptions.New()
        opt.Set(PointOptions.PRECISION, data.precision)
        opt.Set(PointOptions.MAX_SPEED, calc.Kph2Mps(data.maxspeed))
        opt.Set(PointOptions.MARGIN, data.margin)

        if data.lockdir then
            opt.Set(PointOptions.LOCK_DIRECTION, { vehicle.orientation.Forward():Unpack() })
        end
        return opt
    end

    ---Initiates a movement
    ---@param reference Vec3
    ---@param distance number
    ---@param options PointOptions|nil
    local function move(reference, distance, options)
        local route = rc.ActivateTempRoute()
        local point = route.AddCoordinate(vehicle.position.Current() + reference * distance)
        local opt = options or point.Options()

        opt.Set(PointOptions.MAX_SPEED, speed)
        opt.Set(PointOptions.FINAL_SPEED, 0) -- Move and come to a stop

        point.SetOptions(opt)

        flightCore.StartFlight()
    end

    local function printCurrent()
        log:Info("Turn angle: ", turnAngle, "°, step: ", movestep, "m, speed: ", speed, "km/h")
    end

    cmd.Accept("route-list", function(data)
        local routes = rc.GetRouteNames()
        log:Info(#routes, " available routes")
        for _, r in ipairs(routes) do
            log:Info(r)
        end
    end)

    cmd.Accept("route-edit",
        ---@param data {commandValue:string}
        function(data)
            if rc.EditRoute(data.commandValue) then
                log:Info("Route open for edit")
            end
        end).AsString()

    cmd.Accept("route-create",
        ---@param data {commandValue:string}
        function(data)
            rc.CreateRoute(data.commandValue)
        end).AsString().Mandatory()

    cmd.Accept("route-save", function(data)
        rc.SaveRoute()
    end).AsEmpty()

    cmd.Accept("route-delete",
        ---@param data {commandValue:string}
        function(data)
            rc.DeleteRoute(data.commandValue)
        end).AsString().Mandatory()

    cmd.Accept("route-print", function(data)
        local route = rc.CurrentEdit()
        if route == nil then
            log:Error("No route being edited")
            return
        end

        for i, p in ipairs(route.Points()) do
            log:Info(i, ":", calc.Ternary(p.HasWaypointRef(), p.WaypointRef(), p.Pos()))

            local opts = p.Options()
            for k, v in pairs(opts.Data()) do
                log:Info("- ", k, ": ", v)
            end
        end
    end)

    cmd.Accept("route-activate",
        ---@param data {commandValue:string, reverse:boolean}
        function(data)
            local reverse = calc.Ternary(data.reverse or false, RouteOrder.REVERSED, RouteOrder.FORWARD) ---@type RouteOrder

            if rc.ActivateRoute(data.commandValue, reverse) then
                flightCore.StartFlight()
                log:Info("Flight started")
            end
        end).AsString().Mandatory()
        .Option("reverse").AsEmptyBoolean()

    cmd.Accept("route-reverse", function(data)
        if rc.ReverseRoute() then
            log:Info("Route reveresed")
        end
    end)

    local addCurrentToRoute = cmd.Accept("route-add-current-pos", function(data)
        local route = rc.CurrentEdit()

        if not route then
            log:Error("No route open for edit")
            return
        end

        local point = route.AddCurrentPos()
        point.SetOptions(createOptions(data))
        log:Info("Added current position to route")
    end).AsEmpty()

    addPointOptions(addCurrentToRoute)

    local addNamed = cmd.Accept("route-add-named-pos",
        ---@param data {commandValue:string}
        function(data)
            local ref = rc.LoadWaypoint(data.commandValue)

            if ref then
                local route = rc.CurrentEdit()
                if route == nil then
                    log:Error("No route open for edit")
                else
                    local p = route.AddWaypointRef(data.commandValue)
                    if p then
                        p.SetOptions(createOptions(data))
                        log:Info("Added position to route")
                    else
                        log:Error("Could not add postion")
                    end
                end
            end
        end).AsString()
    addPointOptions(addNamed)

    cmd.Accept("route-delete-pos",
        ---@param data {commandValue:number}
        function(data)
            local route = rc.CurrentEdit()
            if route == nil then
                log:Error("No route open for edit")
            else
                if route.RemovePoint(data.commandValue) then
                    log:Info("Point removed")
                else
                    log:Error("Could not remove point")
                end
            end
        end).AsNumber().Mandatory()

    local movePos = cmd.Accept("route-move-pos",
        ---@param data {from:number, to:number}
        function(data)
            local route = rc.CurrentEdit()
            if route == nil then
                log:Error("No route open for edit")
            else
                if route.MovePoint(data.from, data.to) then
                    log:Info("Point moved")
                else
                    log:Error("Could not move point")
                end
            end
        end)
    movePos.Option("from").AsNumber().Mandatory()
    movePos.Option("to").AsNumber().Mandatory()

    cmd.Accept("pos-save-as",
        ---@param data {commandValue:string}
        function(data)
            local pos = universe.CreatePos(vehicle.position.Current()).AsPosString()
            if rc.StoreWaypoint(data.commandValue, pos) then
                log:Info("Position saved as ", data.commandValue)
            end
        end).AsString().Mandatory()

    cmd.Accept("pos-list", function(_)
        for _, data in ipairs(rc.GetWaypoints()) do
            log:Info(data.name, ": ", data.point:Pos())
        end
    end)

    cmd.Accept("pos-delete",
        ---@param data {commandValue:string}
        function(data)
            if rc.DeleteWaypoint(data.commandValue) then
                log:Info("Waypoint deleted")
            end
        end).AsString().Mandatory()

    local rel = cmd.Accept("pos-create-along-gravity",
        ---@param data {commandValue:string, u:number}
        function(data)
            local pos = vehicle.position.Current() - universe.VerticalReferenceVector() * data.u
            local posStr = universe.CreatePos(pos).AsPosString()
            if rc.StoreWaypoint(data.commandValue, posStr) then
                log:Info("Stored postion ", posStr, " as ", data.commandValue)
            end
        end).AsString().Mandatory()
    rel.Option("-u").AsNumber().Mandatory()


    -- Fine tune commands below
    input.Register(keys.forward, Criteria.New().OnRepeat(), function()
        move(vehicle.orientation.Forward(), movestep)
    end)

    input.Register(keys.backward, Criteria.New().OnRepeat(), function()
        move(vehicle.orientation.Forward(), -movestep)
    end)

    input.Register(keys.strafeleft, Criteria.New().OnRepeat(), function()
        local options = PointOptions.New()
        options.Set(PointOptions.MAX_SPEED, speed)
        options.Set(PointOptions.LOCK_DIRECTION, { vehicle.orientation.Forward():Unpack() })

        move(-vehicle.orientation.Right(), movestep, options)
    end)

    input.Register(keys.straferight, Criteria.New().OnRepeat(), function()
        local options = PointOptions.New()
        options.Set(PointOptions.MAX_SPEED, speed)
        options.Set(PointOptions.LOCK_DIRECTION, { vehicle.orientation.Forward():Unpack() })
        move(vehicle.orientation.Right(), movestep, options)
    end)

    input.Register(keys.up, Criteria.New().OnRepeat(), function()
        move(-universe.VerticalReferenceVector(), movestep)
    end)

    input.Register(keys.down, Criteria.New().OnRepeat(), function()
        move(-universe.VerticalReferenceVector(), -movestep)
    end)

    input.Register(keys.yawleft, Criteria.New().OnRepeat(), function()
        flightCore.Turn(turnAngle, vehicle.orientation.Up())
    end)

    input.Register(keys.yawright, Criteria.New().OnRepeat(), function()
        flightCore.Turn(-turnAngle, vehicle.orientation.Up())
    end)

    cmd.Accept("step", function(data)
        movestep = Clamp(data.commandValue, 0.1, 200000)
        printCurrent()
    end).AsNumber().Mandatory()

    cmd.Accept("speed", function(data)
        speed = calc.Kph2Mps(Clamp(data.commandValue, 1, calc.Mps2Kph(construct.getMaxSpeed())))
        printCurrent()
    end).AsNumber().Mandatory()

    cmd.Accept("turn-angle", function(data)
        turnAngle = Clamp(data.commandValue, 0, 360)
        printCurrent()
    end)

    ---@param c Command
    local function addPointOptions(c)
        c.Option("-precision").AsBoolean().Default(false)
        c.Option("-lockdir").AsBoolean().Default(false)
        c.Option("-maxspeed").AsNumber().Default(speed)
        c.Option("-margin").AsNumber().Default(0.1)
    end

    local function createOptions(data)
        local opt = PointOptions.New()
        opt.Set(PointOptions.PRECISION, data.precision)
        opt.Set(PointOptions.MAX_SPEED, calc.Kph2Mps(data.maxspeed))
        opt.Set(PointOptions.MARGIN, data.margin)

        if data.lockdir then
            opt.Set(PointOptions.LOCK_DIRECTION, { vehicle.orientation.Forward():Unpack() })
        end
        return opt
    end

    local moveFunc = function(data)
        local route = rc.ActivateTempRoute()
        local pos = vehicle.position.Current()
        local point = route.AddCoordinate(pos + vehicle.orientation.Forward() * data.f +
            vehicle.orientation.Right() * data.r - universe.VerticalReferenceVector() * data.u)
        point.SetOptions(createOptions(data))

        flightCore.StartFlight()
    end

    local moveCmd = cmd.Accept("move", moveFunc)
    moveCmd.Option("-u").AsNumber().Mandatory().Default(0)
    moveCmd.Option("-r").AsNumber().Mandatory().Default(0)
    moveCmd.Option("-f").AsNumber().Mandatory().Default(0)
    addPointOptions(moveCmd)

    local turnFunc = function(data)
        -- Turn in the expected way, i.e. clockwise on positive values.
        local angle = -data.commandValue

        flightCore.Turn(angle, vehicle.orientation.Up())
    end

    cmd.Accept("turn", turnFunc).AsNumber()

    local strafeFunc = function(data)
        local route = rc.ActivateTempRoute()
        local point = route.AddCoordinate(vehicle.position.Current() +
            vehicle.orientation.Right() * data.commandValue)
        local p = PointOptions.New()
        point.options = p
        p.Set(PointOptions.LOCK_DIRECTION, { vehicle.orientation.Forward():Unpack() })
        p.Set(PointOptions.MAX_SPEED, data.maxspeed or speed)

        flightCore.StartFlight()
    end

    local strafeCmd = cmd.Accept("strafe", strafeFunc).AsNumber()
    strafeCmd.Option("-maxspeed").AsNumber()

    local gotoCmd = cmd.Accept("goto",
        ---@param data {commandValue:string}
        function(data)
            local target
            local point = rc.LoadWaypoint(data.commandValue)
            if point then
                target = point.Pos()
            else
                local pos = universe.ParsePosition(data.commandValue)
                if pos then
                    target = pos.AsPosString()
                end
            end

            if target then
                local route = rc.ActivateTempRoute()
                route.AddCurrentPos()
                local targetPoint = route.AddPos(target)
                targetPoint.SetOptions(createOptions(data))
                flightCore.StartFlight()
                log:Info("Moving to position")
            else
                log:Error("Given position is not a :pos{} string or a named waypoint")
            end
        end).AsString().Mandatory()
    addPointOptions(gotoCmd)

    printCurrent()


    return setmetatable(s, ControlCommands)
end

return ControlCommands