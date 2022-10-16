local r = require("CommonRequire")
local keys = require("input/Keys")
local Criteria = require("input/Criteria")
local PointOptions = require("flight/route/PointOptions")
local CommandLine = require("commandline/CommandLine")
local Input = require("input/Input")
local utils = r.utils

local log = r.log
local vehicle = r.vehicle
local calc = r.calc
local universe = r.universe
local brakes = r.brakes

---@module "flight/FlightCore"

---@class InputHandler
---@field New fun(flightCore.FlightCore)
local InputHandler = {}
InputHandler.__index = InputHandler

---Creates a new InputHandler
---@param flightCore FlightCore
---@return InputHandler
function InputHandler.New(flightCore)
    local s = {}

    local step = 50
    local speed = calc.Kph2Mps(150)

    local routeController = flightCore.GetRoutController()
    local cmd = CommandLine.Instance()
    local input = Input.Instance()

    input.Register(keys.option1, Criteria.New().LAlt().OnPress(), function()
        if player.isFrozen() == 1 then
            player.freeze(false)
            log:Info("Movement enabled")
        else
            player.freeze(true)
            log:Info("Manual mode")
        end
    end)

    local function move(reference, distance, options)
        local route = routeController.ActivateTempRoute()
        local point = route.AddCoordinate(vehicle.position.Current() + reference * distance)
        options = options or point:Options()

        options:Set(PointOptions.MAX_SPEED, speed)
        options:Set(PointOptions.FINAL_SPEED, 0) -- Move and come to a stop

        point.options = options

        flightCore.StartFlight()
    end

    input.Register(keys.forward, Criteria.New().OnRepeat(), function()
        move(vehicle.orientation.Forward(), step)
    end)

    input.Register(keys.backward, Criteria.New().OnRepeat(), function()
        move(vehicle.orientation.Forward(), -step)
    end)

    input.Register(keys.strafeleft, Criteria.New().OnRepeat(), function()
        local options = PointOptions.New()
        options.Set(PointOptions.MAX_SPEED, speed)
        options.Set(PointOptions.LOCK_DIRECTION, { vehicle.orientation.Forward():unpack() })

        move(-vehicle.orientation.Right(), step, options)
    end)

    input.Register(keys.straferight, Criteria.New().OnRepeat(), function()
        local options = PointOptions.New()
        options.Set(PointOptions.MAX_SPEED, speed)
        options.Set(PointOptions.LOCK_DIRECTION, { vehicle.orientation.Forward():unpack() })
        move(vehicle.orientation.Right(), step, options)
    end)

    input.Register(keys.up, Criteria.New().OnRepeat(), function()
        move(-universe.VerticalReferenceVector(), step)
    end)

    input.Register(keys.down, Criteria.New().OnRepeat(), function()
        move(-universe.VerticalReferenceVector(), -step)
    end)

    input.Register(keys.yawleft, Criteria.New().OnRepeat(), function()
        flightCore.Turn(1, vehicle.orientation.Up())
    end)

    input.Register(keys.yawright, Criteria.New().OnRepeat(), function()
        flightCore.Turn(-1, vehicle.orientation.Up())
    end)

    input.Register(keys.brake, Criteria.New().OnPress(), function()
        brakes:Forced(true)
    end)

    input.Register(keys.brake, Criteria.New().OnRelease(), function()
        brakes:Forced(false)
    end)

    local start = vehicle.position.Current()

    input.Register(keys.option9, Criteria.New().OnPress(), function()
        local route = routeController.ActivateTempRoute()
        local point = route.AddCoordinate(start)
        point.Options().Set(PointOptions.MAX_SPEED, speed)

        flightCore.StartFlight()
    end)

    local stepFunc = function(data)
        step = utils.clamp(data.commandValue, 0.1, 20000)
        log:Info("Step set to: ", step)
    end

    cmd.Accept("step", stepFunc).AsNumber().Mandatory()

    local speedFunc = function(data)
        speed = calc.Kph2Mps(utils.clamp(data.commandValue, 1, 20000))
        log:Info("Speed set to: ", speed)
    end

    cmd.Accept("speed", speedFunc).AsNumber().Mandatory()

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
            opt.Set(PointOptions.LOCK_DIRECTION, { vehicle.orientation.Forward():unpack() })
        end
        return opt
    end

    local moveFunc = function(data)
        local route = routeController.ActivateTempRoute()
        local pos = vehicle.position.Current()
        local point = route.AddCoordinate(pos + vehicle.orientation.Forward() * data.f +
            vehicle.orientation.Right() * data.r - universe.VerticalReferenceVector() * data.u)
        point.options = createOptions(data)

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

        flightCore.Turn(angle, vehicle.orientation.Up(), vehicle.position.Current())
    end

    cmd.Accept("turn", turnFunc).AsNumber()

    local strafeFunc = function(data)
        local route = routeController.ActivateTempRoute()
        local point = route.AddCoordinate(vehicle.position.Current() + vehicle.orientation.Right() * data.commandValue)
        local p = PointOptions.New()
        point.options = p
        p.Set(PointOptions.LOCK_DIRECTION, { vehicle.orientation.Forward():unpack() })
        p.Set(PointOptions.MAX_SPEED, data.maxspeed or speed)

        flightCore.StartFlight()
    end

    local strafeCmd = cmd.Accept("strafe", strafeFunc).AsNumber()
    strafeCmd.Option("-maxspeed").AsNumber()

    local listRoutes = function(data)
        local routes = routeController.GetRouteNames()
        log:Info(#routes, " available routes")
        for _, r in ipairs(routes) do
            log:Info(r)
        end
    end

    cmd.Accept("route-list", listRoutes)

    local loadRoute = function(data)
        routeController.LoadRoute(data.commandValue)
    end

    cmd.Accept("route-load", loadRoute).AsString()

    local createRoute = function(data)
        routeController.CreateRoute(data.commandValue)
    end

    cmd.Accept("route-create", createRoute).AsString().Mandatory()

    local routeSave = function(data)
        routeController.SaveRoute()
    end

    cmd.Accept("route-save", routeSave).AsString()

    local deleteRoute = function(data)
        routeController.DeleteRoute(data.commandValue)
    end

    local routeActivate = cmd.Accept("route-activate", function(data)
        local reverse = calc.Ternary(data.reverse or false, RouteOrder.REVERSED, RouteOrder.FORWARD) ---@type RouteOrder

        if routeController.ActivateRoute(data.commandValue, reverse) then
            flightCore.StartFlight()
            log:Info("Flight started")
        end
    end).AsString().Mandatory()
    routeActivate.Option("reverse").AsEmptyBoolean()

    cmd.Accept("route-delete", deleteRoute).AsString()

    local addCurrentPos = function(data)
        local route = routeController.CurrentEdit()

        if not route then
            log:Error("No route open for edit")
            return
        end

        local point = route.AddCurrentPos()
        point.options = createOptions(data)
    end

    local addCurrentToRoute = cmd.Accept("route-add-current-pos", addCurrentPos).AsString()
    addPointOptions(addCurrentToRoute)

    local addNamedPos = function(data)
        local ref = routeController.LoadWaypoint(data.commandValue)

        if ref then
            local route = routeController.CurrentEdit()
            local p = route.AddWaypointRef(data.commandValue)
            p.options = createOptions(data)
        end
    end

    local addNamed = cmd.Accept("route-add-named-pos", addNamedPos).AsString()
    addPointOptions(addNamed)

    local saveAsWaypoint = function(data)
        local pos = universe.CreatePos(vehicle.position.Current()).AsPosString()
        routeController.StoreWaypoint(data.commandValue, pos)
    end

    cmd.Accept("pos-save-as", saveAsWaypoint).AsString().Mandatory()

    cmd.Accept("pos-list", function(_)
        for _, data in ipairs(routeController.GetWaypoints()) do
            log:Info(data.name, ": ", data.point:Pos())
        end
    end)

    return setmetatable(s, InputHandler)
end

return InputHandler