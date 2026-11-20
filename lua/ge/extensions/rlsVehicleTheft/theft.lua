-- Taking a car: the take/store key (M.attempt), the hold-still countdown beside a street car, and
-- opening the case (begin).

return function(ctx)
  local M = ctx.M
  local session = ctx.session
  local config = ctx.config
  local heatHotSeconds, heatWarmSeconds, rules, taxiTheft =
    config.heatHotSeconds, config.heatWarmSeconds, config.rules, config.taxiTheft
  -- From the other parts; bound by the function this file returns once every part is installed.
  local accessDistance, availableStreetCar, bindRls, caseLimit, checkIgnition, enterAsDriver, forceStop,
    forgetForcedStop, gameTime, ignitionBusy, ignitionCoolingDown, inspectedDealer, keyLabel, load, money,
    notify, parkedCars, perk, releaseForcedStop, releaseStreetCar, replaceProp, save, store, streetReportDelay,
    transitCase, walkingPlayer

  -- reward: the XP and theft counters this theft earns ({xp, label, clean, carjacked}). They are paid when the
  -- car is stored, so a car that is ditched or seized before storage earns nothing.
  -- taxi: the car was an RLS cab. Its driver's cash is paid at once (it is in the player's pocket, whatever
  -- becomes of the car) and every pursuit of this case starts at taxiTheft.wantedLevel.
  local function begin(vehicle, source, seller, value, delay, organizationId, immediate, reward, taxi)
    session.liveId = vehicle:getID()
    session.state.serial = session.state.serial + 1
    -- Every case you are already holding makes the report come in sooner.
    delay = delay / (1 + 0.35 * #session.state.cases)
    local reportAt = gameTime() + math.max(1, math.ceil(delay))
    -- A driver who saw the car taken reports it at once, and the message below already says the police are
    -- coming. Marking the case reported keeps a second "reported stolen" message from replacing it a second later.
    table.insert(session.state.cases, {serial = session.state.serial, source = source, seller = seller, value = tonumber(value) or 0,
      reportAt = reportAt, heatHotUntil = reportAt + heatHotSeconds,
      heatWarmUntil = reportAt + heatHotSeconds + heatWarmSeconds, phase = "transit", immediate = immediate or nil,
      reported = immediate and true or nil,
      reward = reward, taxi = taxi or nil, wanted = taxi and taxiTheft.wantedLevel or nil})
    local cash = taxi and math.random(math.floor(taxiTheft.cashMin / 5), math.floor(taxiTheft.cashMax / 5)) * 5
    if cash then
      overhaul_career_economy_payment.reward({money = {amount = cash}},
        {label = "Taxi driver's cash", category = "income", tags = {"vehicleTheft"}}, true)
    end
    session.patrolCheck = 0
    if source == "testDrive" then
      session.state.bans[seller] = gameTime() + 1800
    end
    local reputation = rules[source].reputation
    local organization = reputation and organizationId and overhaul_world_organizations
      and overhaul_world_organizations.getOrganization(organizationId)
    if organization then
      local key = organization.id .. "Reputation"
      overhaul_career_economy_payment.pay({[key] = {amount = reputation, canBeNegative = true}},
        {label = "Dealership vehicle theft", tags = {"vehicleTheft", "fine"}})
      local label = type(organization.name) == "string" and organization.name or organization.id
      ui_message(string.format("Company reputation: -%d (%s)", reputation, label), 7, "rlsVehicleTheftReputation")
    end
    save()
    if cash then
      -- Two short messages instead of one long one: the cash on its own line, like the XP toast, and the
      -- police warning with what to do next. RLS adds its own payment and loudspeaker toasts on top.
      ui_message("Taxi driver's cash: +" .. money(cash), 5, "rlsVehicleTheftCash")
      notify(string.format("Taxi stolen. Police are coming at wanted level %d. Lose them, then store it at a "
        .. "garage you own.", taxiTheft.wantedLevel))
    elseif immediate then
      notify("The driver saw you take the vehicle. Police are responding. Lose them and store it at a garage you own to earn the XP.")
    else
      notify("Vehicle taken. Drive to a garage you own and press " .. keyLabel() .. " to store it and earn the XP.")
    end
  end

  function M.attempt()
    -- Global action bindings can fire while the phone UI has focus (notably mouse buttons).
    if session.appOpen then return end
    if not load() or not gameplay_traffic or not gameplay_walk or not overhaul_integration_services_police then return end
    -- Nothing to take while the player is being booked (custody.lua).
    if session.state.custody then return end
    bindRls()
    local player = walkingPlayer()
    if not player then return end
    if transitCase() then
      if session.liveId == player:getID() then store(player)
      else notify("You are still carrying a stolen car. Store it in a garage you own, or walk away from it, first.") end
      return
    end
    if #session.state.cases >= caseLimit() then
      notify(string.format("You are already handling %d stolen cars. Sell, strip or ditch one before taking another.", #session.state.cases))
      return
    end
    if session.attempted or ignitionBusy() then return end
    if ignitionCoolingDown() then
      notify("Wait a few seconds before trying again.")
      return
    end

    local info, seller, listing, dealer = inspectedDealer()
    local target = info and getObjectByID(info.vehId)
    if target and (target:getID() == player:getID() or accessDistance(target, player) <= 4.5) then
      local drive = overhaul_career_market_testDrive
      -- isActive() is nil before the first test drive and false after one; normalize both.
      local activeDrive = drive.isActive() == true
      if activeDrive and player:getID() ~= info.vehId then return end
      if not activeDrive and not gameplay_walk.isWalking() and player:getID() ~= info.vehId then return end
      checkIgnition(target, seller, activeDrive, function(vehicle, result)
        local delay = activeDrive and (drive.getTimeLeft() or 75) or 6
        if activeDrive then
          drive.resetData()
          overhaul_career_career.setAutosaveEnabled(true)
        end
        overhaul_career_market_inspectVehicle.leaveSaleCallback("dontDespawn", false, false, "Dealership vehicle taken.")
        if be:getPlayerVehicleID(0) ~= info.vehId then enterAsDriver(vehicle) end
        core_vehicleBridge.executeAction(vehicle, "setFreeze", false)
        listing.markedSold, listing.soldViewCounter = true, 1
        begin(vehicle, activeDrive and "testDrive" or "inspection", seller, info.value, delay, dealer.associatedOrganization,
          nil, {xp = activeDrive and 20 or 15, label = "Dealership vehicle theft",
            clean = result and not result.skipped and result.misses == 0 or nil})
      end)
      return
    end

    if not gameplay_walk.isWalking() then
      notify("Approach a stopped civilian vehicle or the dealership car you are inspecting on foot.")
      return
    end
    local nearest, bestDistance
    for _, candidates in ipairs({gameplay_traffic.getTrafficData(), parkedCars()}) do
      for id in pairs(candidates) do
        local car, meters = availableStreetCar(id, player, true)
        if car and (not bestDistance or meters < bestDistance) then nearest, bestDistance = id, meters end
      end
    end
    if not nearest then
      notify("No eligible vehicle nearby. Walk up to a parked car, or step next to a civilian car or taxi driving slower than about 30 km/h.")
      return
    end
    if parkedCars()[nearest] then
      local wait = perk("parkedWait", 4)
      session.attempted = {id = nearest, remaining = wait}
      notify(string.format("Stay beside the vehicle for %d seconds.", wait))
    else
      -- A driver is present: flag the car down and pull them out.
      forceStop(getObjectByID(nearest))
      session.attempted = {id = nearest, remaining = 2.5}
      notify("You flag the car down. Stay next to it while the driver stops.")
    end
  end

  local function updateAttempt(dt)
    local player = walkingPlayer()
    local target = player and gameplay_walk.isWalking() and availableStreetCar(session.attempted.id, player)
    if not target then
      releaseForcedStop(session.attempted.id)
      session.attempted = nil
      notify("Vehicle theft attempt canceled.")
      return
    end
    session.attempted.remaining = session.attempted.remaining - dt
    if session.attempted.remaining > 0 then return end
    session.attempted = nil
    checkIgnition(target, nil, false, function(vehicle, result)
      local fromTraffic = not parkedCars()[vehicle:getID()]
      -- Read before the car leaves traffic, which drops its taxi flag. A cab always has its driver at the
      -- wheel, so it is reported at once, like any carjacking.
      local trafficEntry = fromTraffic and gameplay_traffic.getTrafficData()[vehicle:getID()]
      local taxi = trafficEntry and trafficEntry.isTaxi or nil
      local delay = taxi and 0 or streetReportDelay(vehicle, result)
      if fromTraffic then
        -- The car is ours now: switch its AI off (this also releases the stop mode's parking brake).
        forgetForcedStop(vehicle:getID())
        vehicle:queueLuaCommand('ai.setMode("disabled")')
      end
      if not releaseStreetCar(vehicle) then
        notify("That parked vehicle is no longer available.")
        return false
      end
      vehicle = replaceProp(vehicle)
      if not vehicle then
        notify("The vehicle could not be taken. Try another one.")
        return false
      end
      local id = vehicle:getID()
      enterAsDriver(vehicle)
      -- A carjacked car may still be rolling when the player takes the wheel. Switch the AI off again now that
      -- the player is seated, so no leftover AI mode or parking brake keeps the player from steering it (#10).
      if fromTraffic then vehicle:queueLuaCommand('ai.setMode("disabled")') end
      if not gameplay_traffic.getTrafficData()[id] then gameplay_traffic.insertTraffic(id, true, true) end
      local clean = not result.skipped and result.misses == 0
      begin(vehicle, "street", nil, 0, delay, nil, result.skipped or taxi, {
        xp = result.skipped and 12 or clean and 20 or 15, label = taxi and "Taxi theft" or "Vehicle theft",
        clean = clean or nil, carjacked = (result.skipped and fromTraffic) or nil}, taxi)
      return vehicle
    end)
  end

  ctx.updateAttempt = updateAttempt

  return function()
    accessDistance = ctx.accessDistance
    availableStreetCar = ctx.availableStreetCar
    bindRls = ctx.bindRls
    caseLimit = ctx.caseLimit
    checkIgnition = ctx.checkIgnition
    enterAsDriver = ctx.enterAsDriver
    forceStop = ctx.forceStop
    forgetForcedStop = ctx.forgetForcedStop
    gameTime = ctx.gameTime
    ignitionBusy = ctx.ignitionBusy
    ignitionCoolingDown = ctx.ignitionCoolingDown
    inspectedDealer = ctx.inspectedDealer
    keyLabel = ctx.keyLabel
    load = ctx.load
    money = ctx.money
    notify = ctx.notify
    parkedCars = ctx.parkedCars
    perk = ctx.perk
    releaseForcedStop = ctx.releaseForcedStop
    releaseStreetCar = ctx.releaseStreetCar
    replaceProp = ctx.replaceProp
    save = ctx.save
    store = ctx.store
    streetReportDelay = ctx.streetReportDelay
    transitCase = ctx.transitCase
    walkingPlayer = ctx.walkingPlayer
  end
end
