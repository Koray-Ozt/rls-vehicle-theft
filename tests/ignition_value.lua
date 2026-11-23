-- Run from the repository root: lua tests/ignition_value.lua
package.path = "lua/ge/extensions/?.lua;" .. package.path

local config = dofile("lua/ge/extensions/rlsVehicleTheft/config.lua")
local ctx = {M = {}, config = config}
local vehicle = {partConfig = "vehicles/midsize/luxe.pc"}
function vehicle:getID() return 1 end
function vehicle:getJBeamFilename() return self.model or "midsize" end
function vehicle:queueLuaCommand(command) self.command = command end

path = {splitWithoutExt = function(filename)
  local name = filename:match("([^/\\]+)$") or ""
  return "", name:gsub("%.pc$", "")
end}
FS = {fileExists = function() return true end}
core_vehicles = {
  getModelList = function() return {models = {bx = {}, midsize = {}}} end,
  getModel = function(model)
    if model == "bx" then
      return {model = {default_pc = "base"}, configs = {base = {Value = 12000},
        ["240bx_coupe_lx_A"] = {Value = 70000}}}
    end
    if model == "midsize" then
      return {model = {default_pc = "base"}, configs = {base = {Value = 12000}, luxe = {Value = 45000}}}
    end
  end,
}

dofile("lua/ge/extensions/rlsVehicleTheft/streetCars.lua")(ctx)
assert(ctx.streetVehicleValue(vehicle) == 45000)
vehicle.model, vehicle.partConfig = "simple_traffic", "vehicles/simple_traffic/bx_sport_coupe_parked.pc"
assert(ctx.streetVehicleValue(vehicle) == 70000)
vehicle.partConfig = "vehicles/simple_traffic/midsize_parked.pc"
assert(ctx.streetVehicleValue(vehicle) == 12000)

getObjectByID = function(id) return id == 1 and vehicle end
be = {getObjectActive = function(_, id) return id == 1 end}
gameplay_walk = {isWalking = function() return true end}
extensions = {ui_router = {navigate = function() return true end}}
guihooks = {trigger = function() end}
ctx.walkingPlayer = function() return {getID = function() return 2 end} end
ctx.availableStreetCar = function() return vehicle end
local widthPerk = 1
ctx.perk = function(name, default)
  if name == "ignitionWidth" then return widthPerk end
  return default
end
ctx.notify = function() end
ctx.releaseForcedStop = function() end
ctx.gameTime = function() return 0 end

dofile("lua/ge/extensions/rlsVehicleTheft/ignition.lua")(ctx)()
for _, case in ipairs({
  {value = 15000, label = "Basic security", seconds = 29, width = 1.15, speed = 0.9},
  {value = 60000, label = "Standard security", seconds = 25, width = 1, speed = 1},
  {value = 60001, label = "Advanced security", seconds = 23, width = 0.85, speed = 1.1},
  {value = 90000, label = "Advanced security", seconds = 23, width = 0.85, speed = 1.1, perk = 1.2},
  {value = nil, label = "Standard security", seconds = 25, width = 1, speed = 1},
}) do
  ctx.resetIgnition(true)
  widthPerk = case.perk or 1
  ctx.checkIgnition(vehicle, nil, false, case.value, function() end)
  local token = tonumber(vehicle.command:match("onIgnitionSample%((%d+),"))
  assert(token, "probe token missing")
  ctx.M.onIgnitionSample(token, false)
  local state = ctx.M.getIgnitionState()
  assert(state.difficulty == case.label and state.duration == case.seconds)
  assert(math.abs(state.width - 2 * config.ignitionHalfWidths[1] * case.width * widthPerk / 15) < 0.0001)
  ctx.M.ignitionInput(token, "begin")
  ctx.tickIgnition(1)
  assert(math.abs(ctx.M.getIgnitionState().cursor - config.ignitionSpeeds[1] * case.speed / 15) < 0.0001)
end

-- The second circuit starts from the right, and the next target cannot repeat the previous lock.
ctx.resetIgnition(true)
widthPerk = 1
ctx.checkIgnition(vehicle, nil, false, 45000, function() end)
local token = tonumber(vehicle.command:match("onIgnitionSample%((%d+),"))
ctx.M.onIgnitionSample(token, false)
ctx.M.ignitionInput(token, "begin")
local first = ctx.M.getIgnitionState()
ctx.tickIgnition(first.target * 15 / config.ignitionSpeeds[1])
ctx.M.ignitionInput(token, "lock")
local second = ctx.M.getIgnitionState()
assert(second.matched == 1 and second.cursor == 1)
assert(math.abs(second.target - first.target) * 15 > 3.99)
ctx.tickIgnition(0.5)
ctx.M.ignitionInput(token, "lock")
assert(ctx.M.getIgnitionState().misses == 1)

print("Ignition value tiers, street catalog lookup, and circuit progression passed")
