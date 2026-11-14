-- Which street cars can be taken, and taking one: parked props swapped for their real model,
-- flagging down a moving car, the driver's seat, and the report delay of a street theft.

return function(ctx)
  local config = ctx.config
  local carjackMaxSpeed, carjackReach =
    config.carjackMaxSpeed, config.carjackReach
  local propConfigs = require("rlsVehicleTheft/propConfigs")
  -- From the other parts; bound by the function this file returns once every part is installed.
  local accessDistance, distance, inventory, parkedCars, perk, takeFromTraffic, walkingPlayer

  -- RLS parks "simple_traffic" props (Type PropParked): their configs have no engine, transmission or
  -- drivetrain, so they can never be started or driven. Simplified traffic uses the same model.
  -- A stolen prop is swapped for the real car it shows: propConfigs.lua names the real model and
  -- configuration of each prop config (bx_sport_coupe_parked -> bx/240bx_coupe_lx_A). A prop missing there
  -- falls back to the rule stock traffic uses, the config key's first word as the model (bastion_base -> bastion),
  -- with that model's default configuration.
  -- Returns nil for a normal vehicle, false if no real model exists, or the real model name and the
  -- configuration file to spawn it with (nil for the model's default).
  local realCars = {}
  local function realModelFor(vehicle)
    if vehicle:getJBeamFilename() ~= "simple_traffic" then return nil end
    local _, key = path.splitWithoutExt(vehicle.partConfig or "")
    if not key then return false end
    key = string.gsub(key, "_parked$", "")
    local car = realCars[key]
    if car == nil then
      local model, config = string.match(propConfigs[key] or "", "^([^/]+)/(.+)$")
      model = model or string.match(key, "%w+")
      if model and core_vehicles.getModelList().models[model] then
        local file = config and ("vehicles/" .. model .. "/" .. config .. ".pc")
        if file and not FS:fileExists("/" .. file) then
          log("W", "rlsVehicleTheft", "Prop " .. key .. ": " .. file .. " is missing, using the model's default configuration.")
          file = nil
        end
        car = {model = model, config = file}
      else
        car = false
      end
      realCars[key] = car
    end
    if not car then return false end
    return car.model, car.config
  end

  -- Deletes the prop and spawns the real car it shows in the same place, paint and plate. Returns the new vehicle.
  local function replaceProp(vehicle)
    local model, configFile = realModelFor(vehicle)
    if model == nil then return vehicle end
    if not model then return nil end
    local metallic = vehicle:getMetallicPaintData() or {}
    local options = {
      config = configFile,
      pos = vehicle:getPosition(),
      rot = quatFromDir(vec3(vehicle:getDirectionVector()), vec3(vehicle:getDirectionVectorUp())),
      paint = createVehiclePaint(vehicle.color, metallic[1]),
      paint2 = createVehiclePaint(vehicle.colorPalette0, metallic[2]),
      paint3 = createVehiclePaint(vehicle.colorPalette1, metallic[3]),
      licenseText = vehicle:getDynDataFieldbyName("licenseText", 0),
      autoEnterVehicle = false,
      canSpawnAnotherVehicleCheck = false,
      centeredPosition = true,
      removeWhenNoPositionFound = false,
    }
    -- Remove the prop first so the safe-spawn check does not push the new car away from it.
    vehicle:delete()
    local replacement = core_vehicles.spawnNewVehicle(model, options)
    return replacement or nil
  end

  -- BeamNG's seat system (gameplay_seatOccupants, a level preset) draws a traffic car's AI driver as a dummy
  -- occupant in its driver seat, and the dummy stays after the car leaves traffic. Entering the car then
  -- seats the player in a free passenger seat with passenger permissions, which block driving.
  local function driverSeat(seats, id)
    for _, seat in ipairs(seats.getSeats(id) or {}) do
      if seat.isDriver then return seat end
    end
  end

  -- Puts the player in the driver's seat of a vehicle they just took.
  local function enterAsDriver(vehicle)
    local id = vehicle:getID()
    local seats = gameplay_seatOccupants
    local seat
    if seats and seats.getSeats then
      -- RLS gives older all-passenger seat layouts a driver seat first, as its own walk-in entry does.
      if overhaul_vehicles_legacyDriverSeat then overhaul_vehicles_legacyDriverSeat.refresh(id) end
      seat = driverSeat(seats, id)
      -- clearDummyOccupant only ever removes a dummy, never a player.
      if seat and seat.occupantType == "dummy" and seats.clearDummyOccupant then
        seats.clearDummyOccupant(id, seat.seatId)
      end
    end
    gameplay_walk.getInVehicle(vehicle)
    -- Safety net: if entry still chose a passenger seat, move the player to the now free driver seat.
    local presence = seat and seats.getPlayerPresence and seats.getPlayerPresence(0)
    if presence and presence.vehicleId == id and presence.seatId ~= seat.seatId and seats.setOccupied then
      local ok, err = pcall(seats.setOccupied, id, seat.seatId, 0, nil, "driver")
      if not ok then log("W", "rlsVehicleTheft", "Could not move the player to the driver seat: " .. tostring(err)) end
    end
  end

  -- Carjacking a moving car: the player flags it down from the road beside it and the driver is made to
  -- stop with the vehicle AI's own "stop" mode (lua/vehicle/ai.lua), which brakes to a halt, sets the
  -- parking brake and disables the AI. If the attempt is abandoned the car goes back to traffic.

  local forcedStops = {}

  local function forceStop(vehicle)
    forcedStops[vehicle:getID()] = true
    vehicle:queueLuaCommand('ai.setMode("stop")')
  end

  local function releaseForcedStop(id)
    if not id or not forcedStops[id] then return end
    forcedStops[id] = nil
    local vehicle = getObjectByID(id)
    if vehicle then vehicle:queueLuaCommand('ai.setMode("traffic")') end
  end

  -- RLS cab states (overhaul_integration_services_taxi) in which the taxi is working a ride for the player:
  -- coming to them, waiting for them or driving them. RLS's own taxi fleet policy keeps the police off a cab
  -- in these states, and taking it would break the ride, so only an idle cab (available or off duty) is taken.
  local taxiRideStates = {enRoute = true, pullingOverForPickup = true, waitingForPickup = true, occupied = true,
    pullingOverForDropoff = true, waitingForDropoff = true}

  -- A traffic car that can be taken from its driver: an ordinary civilian car, or an idle RLS taxi. Police,
  -- suspects and the reserved cab RLS keeps back for phone calls are never takeable.
  local function takeableTraffic(id, traffic)
    if not traffic or not traffic.isAi or traffic.reserved or not traffic.role then return false end
    if not traffic.isTaxi then return traffic.role.name == "standard" end
    if traffic.role.name == "police" or traffic.role.name == "suspect" then return false end
    local taxi = overhaul_integration_services_taxi
    local cabState = taxi and taxi.getTaxiState and taxi.getTaxiState(id)
    return not taxiRideStates[cabState or "available"]
  end

  -- moving: also accept a traffic car still driving below carjackMaxSpeed (the first key press).
  local function availableStreetCar(id, player, moving)
    local traffic = gameplay_traffic.getTrafficData()[id]
    local parked = parkedCars()[id]
    local vehicle = getObjectByID(id)
    if not vehicle or not be:getObjectActive(id) or inventory().getInventoryIdFromVehicleId(id)
      or vehicle.isMissionVehicle or (vehicle.missionId and vehicle.missionId ~= "")
      or realModelFor(vehicle) == false then return end
    local speed = vehicle:getVelocity():length()
    if parked then
      if speed > 0.75 or parked.clearedForSpawn
        or not overhaul_integration_services_parking.isParkedPoolVehicle(id) then return end
    elseif not takeableTraffic(id, traffic) then
      return
    elseif speed > ((moving or forcedStops[id]) and carjackMaxSpeed or 0.75) then
      return
    end
    if not parked and (speed > 0.75 or forcedStops[id]) then
      -- A car that is moving, or braking after being flagged down, may stop a few metres past the player.
      local meters = distance(vehicle, player)
      if meters <= (forcedStops[id] and carjackReach + 2 or carjackReach) then return vehicle, meters end
      return
    end
    local meters = accessDistance(vehicle, player)
    if meters <= 4.5 then return vehicle, meters end
  end

  -- Writes why a street car stopped being takeable to the game log, so a report of "car no longer available"
  -- can be traced to the check that failed. Never throws.
  local function logStreetCarState(event, id)
    local ok, text = pcall(function()
      local vehicle = getObjectByID(id)
      if not vehicle then return "vehicle gone" end
      local player = walkingPlayer()
      local parking = overhaul_integration_services_parking
      local parked = parkedCars()[id]
      local pool = core_vehicleActivePooling.getPoolOfVeh and core_vehicleActivePooling.getPoolOfVeh(id)
      return string.format(
        "active=%s speed=%.2f parkedData=%s cleared=%s poolMember=%s pool=%s isParkedField=%s walking=%s dist=%s",
        tostring(be:getObjectActive(id)), vehicle:getVelocity():length(), tostring(parked ~= nil),
        tostring(parked and parked.clearedForSpawn), tostring(parking and parking.isParkedPoolVehicle(id)),
        tostring(pool and pool.name), tostring(vehicle.isParked), tostring(gameplay_walk.isWalking()),
        player and string.format("%.1f", accessDistance(vehicle, player)) or "nil")
    end)
    log("W", "rlsVehicleTheft", event .. " | id=" .. tostring(id) .. " " .. (ok and text or ("state failed: " .. tostring(text))))
  end

  local function releaseStreetCar(vehicle)
    local id = vehicle:getID()
    local parked = parkedCars()[id]
    if parked then
      local parking = overhaul_integration_services_parking
      local pooling = core_vehicleActivePooling
      local pool = pooling.getPool("overhaulParking")
      if not (pool and pool:removeVeh(id)) then
        -- The car may be held by another pool (or by none). Take it out of whichever pool holds it, and fail
        -- only if a pool still refuses to let go.
        local holder = pooling.getPoolOfVeh and pooling.getPoolOfVeh(id)
        if holder and not holder:removeVeh(id) then
          logStreetCarState("parked car could not be removed from its pool", id)
          return false
        end
      end
      local spots = parking.getParkingSpots()
      local spot = spots and spots.objects and spots.objects[parked.parkingSpotId]
      if spot and spot.vehicle == id then spot.vehicle = nil end
      parking.removeVehicle(id)
      vehicle:setDynDataFieldbyName("ignoreTraffic", 0, "")
      vehicle:setDynDataFieldbyName("isParked", 0, "")
      vehicle.playerUsable = true
      gameplay_walk.removeVehicleFromBlacklist(id)
    else
      local entry = gameplay_traffic.getTrafficData()[id]
      if entry and entry.isTaxi then
        -- RLS blocks walk-in entry to an off-duty cab (playerUsable false, walk blacklist). The player is
        -- taking it, so let them in. Removing it from traffic also releases its cab driver and taxi state.
        vehicle.playerUsable = true
        gameplay_walk.removeVehicleFromBlacklist(id)
      end
      takeFromTraffic(id)
    end
    return true
  end

  local function countWitnesses(vehicle)
    local witnesses = 0
    for id, entry in pairs(gameplay_traffic.getTrafficData()) do
      local other = getObjectByID(id)
      if other and id ~= vehicle:getID() and entry.isAi and be:getObjectActive(id)
        and distance(other, vehicle) < 32 then witnesses = witnesses + 1 end
    end
    return witnesses
  end

  -- Street report delay in seconds.
  -- Carjacking (driver present): reported at once.
  -- Parked car: a clean bypass goes unnoticed until the owner returns (90-180 s);
  -- each missed signal trips the alarm and divides that time; two or more nearby witnesses cut it further.
  local function streetReportDelay(vehicle, result)
    if result.skipped then return 0 end
    local misses = result.misses or 0
    local delay = math.random(90, 180) / (1 + 2 * misses)
    if misses == 0 then delay = delay * perk("quietEntry", 1) end
    if countWitnesses(vehicle) >= 2 then
      delay = misses > 0 and 8 or math.min(delay, 45)
    end
    return delay
  end

  -- The car is the player's now: forget it was flagged down, without handing it back to traffic.
  local function forgetForcedStop(id)
    forcedStops[id] = nil
  end

  -- A new profile or level: forget the cars that were flagged down.
  local function resetForcedStops()
    forcedStops = {}
  end

  ctx.availableStreetCar = availableStreetCar
  ctx.enterAsDriver = enterAsDriver
  ctx.forceStop = forceStop
  ctx.forgetForcedStop = forgetForcedStop
  ctx.logStreetCarState = logStreetCarState
  ctx.releaseForcedStop = releaseForcedStop
  ctx.releaseStreetCar = releaseStreetCar
  ctx.replaceProp = replaceProp
  ctx.resetForcedStops = resetForcedStops
  ctx.streetReportDelay = streetReportDelay

  return function()
    accessDistance = ctx.accessDistance
    distance = ctx.distance
    inventory = ctx.inventory
    parkedCars = ctx.parkedCars
    perk = ctx.perk
    takeFromTraffic = ctx.takeFromTraffic
    walkingPlayer = ctx.walkingPlayer
  end
end
