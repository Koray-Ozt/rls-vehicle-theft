-- Storing the stolen car in a garage the player owns.

return function(ctx)
  local session = ctx.session
  -- From the other parts; bound by the function this file returns once every part is installed.
  local baseColor, caseVehicleId, count, grantXp, inventory, keyLabel, notify, openScrapDialog, recordColor,
    save, transitCase

  -- The owned garage whose entrance is within reach of the vehicle, if any.
  local function ownedGarageNear(vehicle)
    local garage = inventory().getClosestGarage(vehicle:getPosition())
    local door = garage and overhaul_world_facilities.getAverageDoorPositionForFacility(garage)
    if door and door:distance(vehicle:getPosition()) <= 35
      and overhaul_career_garage_garageManager.isPurchasedGarage(garage.id) then return garage end
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
      if not auto or message ~= session.lastStoreRefusal then notify(message) end
      session.lastStoreRefusal = message
    end
    local pursuit = overhaul_integration_services_police.getPursuitData(session.liveId)
    -- Mode -1 is an arrest in progress, not a lost pursuit.
    if pursuit and (pursuit.mode or 0) ~= 0 then
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
    if not id then return end
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
