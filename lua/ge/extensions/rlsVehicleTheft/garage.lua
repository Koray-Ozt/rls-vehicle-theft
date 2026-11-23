-- Storing the stolen car in a garage the player owns.

return function(ctx)
  local session = ctx.session
  -- From the other parts; bound by the function this file returns once every part is installed.
  local baseColor, carChased, caseVehicleId, count, grantXp, inventory, keyLabel, notify, openScrapDialog, recordColor,
    save, transitCase

  -- Distance on the map, ignoring height. A garage without doors is placed at the centre of its zone and
  -- RLS puts that point at the terrain height, which is 0 under a pier or platform (Dockside Garage sits at
  -- z 75 and its reference point at z 0), so a 3D distance would never come within reach of such a garage.
  local function flatDistance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
  end

  -- The owned garage whose entrance is within reach of the vehicle, if any. Every owned garage is
  -- measured, not only the one RLS finds closest in 3D, which that same height error can get wrong.
  local function ownedGarageNear(vehicle)
    local position = vehicle:getPosition()
    local manager = overhaul_career_garage_garageManager
    local facilities = overhaul_world_facilities.getFacilities(getCurrentLevelIdentifier())
    local best, bestDistance = nil, 35
    for _, garage in pairs(facilities and facilities.garages or {}) do
      local door = manager.isPurchasedGarage(garage.id) and overhaul_world_facilities.getAverageDoorPositionForFacility(garage)
      local meters = door and flatDistance(door, position)
      if meters and meters <= bestDistance then best, bestDistance = garage, meters end
    end
    return best
  end

  -- Storing refusals are only on-screen messages; these lines leave a trace in beamng.log (tag rlsVehicleTheft).
  local function trace(message)
    log("I", "rlsVehicleTheft", message)
  end

  -- One line on where the car is relative to the closest garage, for the log: which garage RLS finds closest,
  -- how far its door/zone centre is, and whether the player owns it.
  local function describeGarage(vehicle)
    local garage = inventory().getClosestGarage(vehicle:getPosition())
    if not garage then return "closest garage: none" end
    local door = overhaul_world_facilities.getAverageDoorPositionForFacility(garage)
    return string.format("closest garage: %s, distance: %s, owned: %s", tostring(garage.id),
      door and string.format("~%d m (map), reference height %.0f vs car %.0f", math.floor(flatDistance(door, vehicle:getPosition()) / 10) * 10,
        door.z, vehicle:getPosition().z) or "no position",
      tostring(overhaul_career_garage_garageManager.isPurchasedGarage(garage.id)))
  end

  -- Same test the RLS garage computer uses to list a vehicle (inventory/ui.lua vehicleOverlapsZone):
  -- any node inside one of the garage's zones. A car stored outside them never shows on the computer.
  local function insideGarage(vehicle, garage)
    local zones = overhaul_world_facilities.getZonesForFacility(garage)
    if not zones then return false end
    local origin = vehicle:getPosition()
    for _, zone in ipairs(zones) do
      for nodeId = 0, vehicle:getNodeCount() - 1 do
        if zone:containsPoint2D(vehicle:getNodePosition(nodeId) + origin) then return true end
      end
    end
    return false
  end

  -- auto: called every second after the player leaves the car; repeat a refusal only when it changes.

  local function store(vehicle, auto)
    local case = transitCase()
    if not case then return end
    local function refuse(message)
      if message ~= session.lastStoreRefusal then
        trace(string.format("store refused (%s): %s | speed %.1f m/s", auto and "auto" or "key", message,
          vehicle:getVelocity():length()))
      end
      if not auto or message ~= session.lastStoreRefusal then notify(message) end
      session.lastStoreRefusal = message
    end
    -- Mode -1 is an arrest in progress, not a lost pursuit. Police chasing the player on foot count too.
    if carChased(session.liveId) then
      refuse("Lose the police before storing the vehicle.")
      return
    end
    local garage = ownedGarageNear(vehicle)
    local manager = overhaul_career_garage_garageManager
    if not garage then
      refuse("Drive into a garage you own.")
      return
    end
    -- RLS silently reroutes vehicles away from a garage listed for sale.
    if manager.isGarageForSale and manager.isGarageForSale(garage.id) then
      refuse("This garage is listed for sale. Use another garage you own.")
      return
    end
    if not inventory().hasFreeSlot() then
      -- Every slot is taken. Rather than lose the car, offer to have it stripped for parts. The offer is a
      -- confirmation screen opened by the key press, never by the automatic check.
      if auto then
        refuse(string.format("No free garage slot. Press %s to sell the car for parts, or free a slot first.", keyLabel()))
      elseif session.scrapDialog then
        return
      elseif vehicle:getVelocity():length() > 1 then
        refuse("Stop the vehicle before selling it for parts.")
      else
        openScrapDialog(case)
      end
      return
    end
    local space = manager.isGarageSpace(garage.id)
    if not space or not space[1] then
      refuse("This garage has no free vehicle slots. Use another garage.")
      return
    end
    if not insideGarage(vehicle, garage) then
      refuse("Park the vehicle inside the garage, not at the entrance.")
      return
    end
    if vehicle:getVelocity():length() > 1 then
      refuse("Stop the vehicle inside the garage.")
      return
    end
    local id = inventory().addVehicle(session.liveId, nil, {owned = true, takesNoInventorySpace = false})
    if not id then
      trace("store failed: RLS addVehicle returned no inventory id for vehicle " .. tostring(session.liveId))
      return
    end
    trace(string.format("store ok: vehicle %s added as inventory id %s in garage %s", tostring(session.liveId), tostring(id), tostring(garage.id)))
    case.inventoryId, case.phase = id, "stored"
    local record = inventory().getVehicles()[id]
    record.rlsTheftCase = case.serial
    -- Remember the colour from the theft report. If the record has no paints yet, seed them from the
    -- object the same way RLS's parking respawn does, so later comparisons read one source.
    if not recordColor(id) and record.config then
      local metallic = vehicle:getMetallicPaintData() or {}
      local ok, paint = pcall(createVehiclePaint, vehicle.color, metallic[1])
      if ok and baseColor(paint) then record.config.paints = {paint} end
    end
    case.paint = recordColor(id)
    -- RLS keeps a vehicle it could not place (career/garage/inventory.lua moveVehicleToGarage) in the inventory
    -- without a garage. That is a game-side problem, not a police matter: the case stays open and the car is yours.
    local placed = inventory().moveVehicleToGarage(id, garage.id)
    inventory().setVehicleDirty(id)
    case.value = math.max(case.value, tonumber(overhaul_career_market_valueCalculator.getInventoryVehicleSellValue(id)) or 0)
    -- From here the case follows the inventory id; a stale object id could match an unrelated vehicle later.
    session.liveId = nil
    session.lastStoreRefusal = nil
    session.parkedTicks = 0
    local reward = case.reward
    case.reward = nil
    if reward then
      count("stolen")
      if reward.clean then count("cleanBypass") end
      if reward.carjacked then count("carjacked") end
    end
    save()
    if placed then
      notify("Vehicle stored. At the garage computer, change its identity and repaint it; the original paint is in the theft report.")
    else
      notify("The vehicle is in your inventory, but RLS could not assign it a garage slot. Free a slot and move it into a garage.")
    end
    grantXp(10 + (reward and tonumber(reward.xp) or 0), reward and (reward.label .. ", vehicle stored") or "Stolen vehicle stored")
    return true
  end

  -- True while the player drives the case's car outside an owned garage. Only getting in does not count.
  local function drivenOutOfGarage(case)
    local vehId = caseVehicleId(case)
    if not vehId or be:getPlayerVehicleID(0) ~= vehId then return false end
    local vehicle = getObjectByID(vehId)
    local garage = vehicle and ownedGarageNear(vehicle)
    return vehicle ~= nil and not (garage and insideGarage(vehicle, garage))
  end

  -- Storing used to depend on a key press the player only heard about once. Remind them near an owned
  -- garage, and store automatically when they park inside it and get out. Called every second for the
  -- transit case; returns true once the car is stored.
  -- parkedTicks belongs to the transit case alone: other open cases must not reset it.
  local function updateStorage(case)
    local stolen = session.liveId and getObjectByID(session.liveId)
    -- Log only when the picture changes: stolen car found, near an owned garage, driven or walking.
    local state = stolen and string.format("car found | near owned garage: %s | %s | %s",
      tostring(ownedGarageNear(stolen) ~= nil), be:getPlayerVehicleID(0) == session.liveId and "driving it" or
      (gameplay_walk.isWalking() and "on foot" or "in another vehicle"), describeGarage(stolen))
      or string.format("stolen car object missing (liveId %s)", tostring(session.liveId))
    if state ~= session.storageTrace then
      session.storageTrace = state
      trace("storage check: " .. state)
    end
    if stolen and ownedGarageNear(stolen) then
      if be:getPlayerVehicleID(0) == session.liveId then
        -- A car that is only parked, never stored, is not in the inventory: saving and reloading would lose it.
        -- Once it sits still inside the garage, store it without waiting for a key press or for the player to get out.
        if stolen:getVelocity():length() <= 1 then
          session.parkedTicks = session.parkedTicks + 1
          if session.parkedTicks >= 3 and store(stolen, true) then return true end
        else
          session.parkedTicks = 0
        end
        ui_message("Stolen vehicle: stop inside the garage and it will be stored (or press " .. keyLabel() .. ").",
          2, "rlsVehicleTheftStore")
      elseif gameplay_walk.isWalking() and store(stolen, true) then
        return true
      end
    else
      session.parkedTicks = 0
    end
    return false
  end

  ctx.drivenOutOfGarage = drivenOutOfGarage
  ctx.ownedGarageNear = ownedGarageNear
  ctx.store = store
  ctx.updateStorage = updateStorage

  return function()
    baseColor = ctx.baseColor
    carChased = ctx.carChased
    caseVehicleId = ctx.caseVehicleId
    count = ctx.count
    grantXp = ctx.grantXp
    inventory = ctx.inventory
    keyLabel = ctx.keyLabel
    notify = ctx.notify
    openScrapDialog = ctx.openScrapDialog
    recordColor = ctx.recordColor
    save = ctx.save
    transitCase = ctx.transitCase
  end
end
