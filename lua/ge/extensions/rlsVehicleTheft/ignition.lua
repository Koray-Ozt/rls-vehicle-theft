-- Ignition bypass minigame (ui IgnitionBypass.vue) and starting the engine after a theft.

return function(ctx)
  local M = ctx.M
  local config = ctx.config
  local ignitionFailCooldown, ignitionGrace, ignitionHalfWidths, ignitionLostGrace, ignitionMissPenalty, ignitionRoute, ignitionSpeeds, ignitionStages, ignitionValueTiers =
    config.ignitionFailCooldown, config.ignitionGrace, config.ignitionHalfWidths, config.ignitionLostGrace, config.ignitionMissPenalty, config.ignitionRoute, config.ignitionSpeeds, config.ignitionStages, config.ignitionValueTiers
  -- From the other parts; bound by the function this file returns once every part is installed.
  local accessDistance, availableStreetCar, gameTime, inspectedDealer, logStreetCarState, notify, perk,
    releaseForcedStop, walkingPlayer

  local ignition, ignitionToken, ignitionCooldown = nil, 0, 0
  -- Misses of an abandoned bypass, per vehicle (not saved): the alarm a miss trips stays tripped on a retry.
  local bypassMisses = {}
  -- The engine start after a theft (see finishIgnition and updateStarter).
  local starter

  local function difficultyFor(value)
    value = tonumber(value)
    if not value or value <= 0 or value >= math.huge then return ignitionValueTiers[2] end
    for _, tier in ipairs(ignitionValueTiers) do
      if not tier.maxValue or value <= tier.maxValue then return tier end
    end
    return ignitionValueTiers[2]
  end

  local function nextTarget(previous)
    if not previous then return math.random(4, 12) end
    local choices = {}
    for target = 4, 12 do
      if math.abs(target - previous) >= 4 then choices[#choices + 1] = target end
    end
    return choices[math.random(1, #choices)]
  end
  local function canContinueIgnition(challenge)
    local vehicle = getObjectByID(challenge.id)
    local player = walkingPlayer()
    if not vehicle or not player or not be:getObjectActive(challenge.id) then return end
    if challenge.seller then
      local info, seller = inspectedDealer()
      if not info or info.vehId ~= challenge.id or seller ~= challenge.seller then return end
      if (overhaul_career_market_testDrive.isActive() == true) ~= challenge.testDrive then return end
      if player:getID() == challenge.id or (gameplay_walk.isWalking() and accessDistance(vehicle, player) <= 4.5) then
        return vehicle
      end
    else
      if gameplay_walk.isWalking() then return availableStreetCar(challenge.id, player) end
    end
  end

  local function finishIgnition(challenge, vehicle, startMotor)
    ignition = nil
    bypassMisses[challenge.id] = nil
    -- skipped: the engine was already running (a driver was present), so no bypass was needed.
    -- complete() returns false to abort, or the vehicle actually taken when it replaced a prop.
    local taken = challenge.complete(vehicle, {skipped = not startMotor, misses = challenge.misses or 0})
    if taken == false then return end
    local replaced = taken and taken ~= vehicle
    if taken then vehicle = taken end
    -- A stolen car should leave with its engine running. A replaced prop spawns with the ignition off, and
    -- a parked car has no driver; the starter only cranks when the engine is not already running.
    if startMotor or replaced or not challenge.seller then
      starter = {id = vehicle:getID(), token = challenge.token, elapsed = 0, untilSample = 0.15}
    end
  end

  function M.onStarterSample(token, running, brake)
    if not starter or starter.token ~= token or not running then return end
    local vehicle = getObjectByID(starter.id)
    if vehicle then vehicle:queueLuaCommand("electrics.setIgnitionLevel(2)") end
    starter = nil
    ui_message(brake and "Engine running. Release the parking brake to drive." or "Engine running.",
      5, "rlsVehicleTheftEngine")
  end

  local function updateStarter(dt)
    if not starter then return end
    local vehicle = getObjectByID(starter.id)
    if not vehicle or be:getPlayerVehicleID(0) ~= starter.id then
      if vehicle and starter.cranked then vehicle:queueLuaCommand("electrics.setIgnitionLevel(2)") end
      starter = nil
      return
    end
    starter.elapsed = starter.elapsed + dt
    starter.untilSample = starter.untilSample - dt
    -- A replaced prop is still loading for the first moments, and a cold diesel cuts fuel for ~2 s while cranking.
    if starter.elapsed >= 8 then
      vehicle:queueLuaCommand("electrics.setIgnitionLevel(2)")
      starter = nil
      ui_message("Engine did not start. Try the normal ignition control. A damaged or out-of-fuel vehicle may need a tow.",
        7, "rlsVehicleTheftEngine")
    elseif starter.untilSample <= 0 then
      starter.untilSample = 0.25
      starter.cranked = true
      vehicle:queueLuaCommand(string.format([[
        local e = electrics.values
        local running = e.engineRunning == 1 or e.engineRunning == true
        if e.engineRunning == nil and type(e.rpm) == "number" then running = e.rpm > 300 end
        if not running and e.ignitionLevel ~= 3 then electrics.setIgnitionLevel(3) end
        obj:queueGameEngineLua("rlsVehicleTheft.onStarterSample(%d," .. tostring(running) .. "," ..
          tostring((e.parkingbrake or 0) > 0.5) .. ")")
      ]], starter.token))
    end
  end

  local function checkIgnition(vehicle, seller, testDrive, value, complete)
    ignitionToken = ignitionToken + 1
    ignition = {id = vehicle:getID(), token = ignitionToken, seller = seller, testDrive = testDrive,
      value = value, complete = complete, probeTime = 2}
    vehicle:queueLuaCommand(string.format([[
      local e = electrics and electrics.values or {}
      local running = e.engineRunning == true or e.engineRunning == 1
      if e.engineRunning == nil then
        if type(e.rpm) == "number" then running = e.rpm > 300
        else running = (e.ignitionLevel or 0) >= 2 end
      end
      obj:queueGameEngineLua("rlsVehicleTheft.onIgnitionSample(%d," .. tostring(running) .. ")")
    ]], ignitionToken))
  end

  local function closeIgnition(challenge)
    ignition = nil
    if challenge.stage then extensions.ui_router.navigate("play") end
  end

  local function failIgnition(challenge, message)
    closeIgnition(challenge)
    releaseForcedStop(challenge.id)
    if challenge.stage then bypassMisses[challenge.id] = challenge.misses or 0 end
    ignitionCooldown = gameTime() + ignitionFailCooldown
    notify(message)
  end

  -- Ends a bypass the player walked away from (Cancel, or the screen closed some other way). Once the attempt
  -- has started this counts like a failure: the misses carry over to the next attempt on this car and the retry
  -- waits out the cooldown, so canceling after a miss cannot wipe the alarm. leaving: the screen is already
  -- closing, so do not navigate.
  local function abortIgnition(challenge, message, leaving)
    if leaving then ignition = nil else closeIgnition(challenge) end
    releaseForcedStop(challenge.id)
    if challenge.started then
      bypassMisses[challenge.id] = challenge.misses or 0
      ignitionCooldown = gameTime() + ignitionFailCooldown
    end
    if message then notify(message) end
  end

  local function ignitionSignalAt(challenge, time)
    local cursor = (math.max(0, time) * ignitionSpeeds[challenge.stage] * challenge.speedScale) % 30
    if cursor > 15 then cursor = 30 - cursor end
    -- The middle circuit sweeps from the other side, so all three locks do not play identically.
    if challenge.stage % 2 == 0 then cursor = 15 - cursor end
    return cursor, math.abs(cursor - challenge.target) <= ignitionHalfWidths[challenge.stage] * (challenge.widthScale or 1)
  end

  local function ignitionSignal(challenge)
    return ignitionSignalAt(challenge, challenge.time)
  end

  -- True if the marker is in the zone now or was within the grace window the player is seeing.
  local function ignitionLockHits(challenge)
    for step = 0, 4 do
      local _, inTarget = ignitionSignalAt(challenge, challenge.time - ignitionGrace * step / 4)
      if inTarget then return true end
    end
    return false
  end

  function M.getIgnitionState()
    local challenge = ignition
    if not challenge or not challenge.stage then return nil end
    local cursor, inTarget = ignitionSignal(challenge)
    return {token = challenge.token, cursor = cursor / 15, target = challenge.target / 15,
      width = 2 * ignitionHalfWidths[challenge.stage] * (challenge.widthScale or 1) / 15, matched = challenge.stage - 1, stages = ignitionStages,
      remaining = challenge.remaining, duration = challenge.duration, difficulty = challenge.difficulty,
      inTarget = inTarget,
      started = challenge.started == true, feedback = challenge.feedback ~= nil,
      missed = challenge.feedbackKind == "miss", misses = challenge.misses or 0,
      penalty = challenge.missPenalty or ignitionMissPenalty}
  end

  local function publishIgnition()
    guihooks.trigger("RlsTheftIgnitionState", M.getIgnitionState())
  end

  function M.onIgnitionSample(token, running)
    local challenge = ignition
    if not challenge or challenge.token ~= token or challenge.stage then return end
    local vehicle = canContinueIgnition(challenge)
    if not vehicle then
      ignition = nil
      releaseForcedStop(challenge.id)
      notify("The vehicle is no longer available for ignition bypass.")
      return
    end
    if running then
      finishIgnition(challenge, vehicle, false)
      return
    end
    local tier = difficultyFor(challenge.value)
    challenge.stage, challenge.time, challenge.remaining = 1, 0, tier.seconds
    challenge.duration, challenge.difficulty, challenge.speedScale = tier.seconds, tier.label, tier.speed
    -- Vehicle Theft perks, fixed for this attempt.
    challenge.widthScale = tier.width * perk("ignitionWidth", 1)
    challenge.missPenalty = perk("missPenalty", ignitionMissPenalty)
    challenge.target = nextTarget()
    challenge.frame, challenge.idle = 0, 0
    challenge.misses = bypassMisses[challenge.id] or 0
    if challenge.misses > 0 then notify("The alarm on this car is still tripped from your last attempt.") end
    if extensions.ui_router.navigate(ignitionRoute) == false then
      ignition = nil
      notify("Could not open the ignition bypass screen.")
    end
  end

  function M.ignitionInput(token, action)
    local challenge = ignition
    if not challenge or challenge.token ~= token or not challenge.stage then return end
    if action == "leave" then
      abortIgnition(challenge, challenge.started and "Ignition bypass abandoned." or nil, true)
      return
    end
    if action == "cancel" then
      abortIgnition(challenge, challenge.started
        and string.format("Ignition bypass canceled. Wait %d seconds before trying again.", ignitionFailCooldown)
        or "Ignition bypass canceled.")
      return
    end
    local vehicle = canContinueIgnition(challenge)
    if not vehicle then
      failIgnition(challenge, "You moved out of reach of the vehicle.")
      return
    end
    if action == "begin" and not challenge.started then
      challenge.started = true
      publishIgnition()
    elseif action == "lock" and challenge.started and not challenge.feedback then
      if not ignitionLockHits(challenge) then
        -- A miss costs time instead of ending the attempt; the timer decides failure.
        -- Misses also trip the alarm, which shortens the street report delay.
        challenge.misses = (challenge.misses or 0) + 1
        challenge.remaining = challenge.remaining - (challenge.missPenalty or ignitionMissPenalty)
        if challenge.remaining <= 0 then
          failIgnition(challenge, string.format("Time ran out. Wait %d seconds before trying again.", ignitionFailCooldown))
          return
        end
        challenge.feedback, challenge.feedbackKind = 0.6, "miss"
        publishIgnition()
      elseif challenge.stage == ignitionStages then
        closeIgnition(challenge)
        finishIgnition(challenge, vehicle, true)
      else
        challenge.stage = challenge.stage + 1
        challenge.target = nextTarget(challenge.target)
        challenge.time, challenge.feedback, challenge.feedbackKind = 0, 0.5, "match"
        publishIgnition()
      end
    end
  end

  local function updateIgnition(dt)
    local challenge = ignition
    if not canContinueIgnition(challenge) then
      -- RLS can deactivate or shuffle a parked car for a moment. Pause the attempt and give up only if the car
      -- stays unavailable for a while.
      challenge.lost = (challenge.lost or 0) + dt
      if challenge.lost > ignitionLostGrace then
        if not challenge.seller then logStreetCarState("ignition bypass lost the vehicle", challenge.id) end
        failIgnition(challenge, "The vehicle is no longer available for ignition bypass.")
      end
      return
    end
    challenge.lost = nil
    if not challenge.stage then
      challenge.probeTime = challenge.probeTime - dt
      if challenge.probeTime <= 0 then failIgnition(challenge, "Could not read the ignition. Try again.") end
      return
    end
    if not challenge.started then
      challenge.idle = challenge.idle + dt
      if challenge.idle > 45 then abortIgnition(challenge, "Ignition bypass closed.") end
      return
    end
    challenge.remaining = challenge.remaining - dt
    if challenge.remaining <= 0 then
      failIgnition(challenge, string.format("Time ran out. Wait %d seconds before trying again.", ignitionFailCooldown))
      return
    end
    if challenge.feedback then
      challenge.feedback = challenge.feedback - dt
      if challenge.feedback <= 0 then challenge.feedback, challenge.feedbackKind = nil, nil end
    else
      challenge.time = challenge.time + dt
    end
    challenge.frame = challenge.frame + dt
    if challenge.frame >= 1 / 30 then
      challenge.frame = 0
      publishIgnition()
    end
  end

  -- True while a bypass is being probed or played: a new theft attempt waits for it.
  local function ignitionBusy()
    return ignition ~= nil
  end

  -- True while the wait after a failed or abandoned bypass runs.
  local function ignitionCoolingDown()
    return gameTime() < ignitionCooldown
  end

  -- Every frame: the running bypass and the engine start after a theft.
  local function tickIgnition(dt)
    if ignition then updateIgnition(dt) end
    updateStarter(dt)
  end

  -- The career is not loaded: drop a bypass in progress.
  local function dropIgnition()
    ignition = nil
  end

  -- A new level (or, with clearCooldown, a new profile): nothing of a bypass carries over.
  local function resetIgnition(clearCooldown)
    ignition, starter = nil, nil
    bypassMisses = {}
    if clearCooldown then ignitionCooldown = 0 end
  end

  ctx.checkIgnition = checkIgnition
  ctx.dropIgnition = dropIgnition
  ctx.ignitionBusy = ignitionBusy
  ctx.ignitionCoolingDown = ignitionCoolingDown
  ctx.resetIgnition = resetIgnition
  ctx.tickIgnition = tickIgnition

  return function()
    accessDistance = ctx.accessDistance
    availableStreetCar = ctx.availableStreetCar
    gameTime = ctx.gameTime
    inspectedDealer = ctx.inspectedDealer
    logStreetCarState = ctx.logStreetCarState
    notify = ctx.notify
    perk = ctx.perk
    releaseForcedStop = ctx.releaseForcedStop
    walkingPlayer = ctx.walkingPlayer
  end
end
