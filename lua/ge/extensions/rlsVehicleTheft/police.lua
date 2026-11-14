-- Police on stolen cars: the theft report, patrol sightings, undercover stings and pursuit outcomes.

return function(ctx)
  local M = ctx.M
  local session = ctx.session
  local config = ctx.config
  local heatHotSeconds, heatWarmSeconds, sightRanges, stingSeconds =
    config.heatHotSeconds, config.heatWarmSeconds, config.sightRanges, config.stingSeconds
  -- From the other parts; bound by the function this file returns once every part is installed.
  local caseForVehicle, caseVehicleId, count, disguised, distance, findCase, gameTime, grantXp, heatStatus,
    inventory, notify, paintRecognitionChance, recordColor, save, seize

  -- Undercover buyers ---------------------------------------------------------------------------------
  -- Accepting an undercover cop's offer is a sting, not a sale. The listing is gone and the car stays yours,
  -- but the police now know its new plate and the colour the buyer saw, so it is back to an undisguised,
  -- freshly reported car: it needs another identity change and another repaint. state.sting then hunts the
  -- seller: the next vehicle the player drives (at once if they are driving) gets an immediate pursuit, like a
  -- carjacking report. Lose it and the operation ends; get arrested and the car is seized with the theft fine.

  -- Starts the sting pursuit on the vehicle the player is driving. Returns true once a chase is on.
  local function startStingPursuit()
    local sting = session.state.sting
    if not sting or sting.pursuing then return false end
    local vehId = be:getPlayerVehicleID(0)
    if not vehId or vehId < 0 or not getObjectByID(vehId) or (gameplay_walk and gameplay_walk.isWalking()) then
      return false
    end
    local police = overhaul_integration_services_police
    if not police then return false end
    local pursuit = police.getPursuitData(vehId)
    if not pursuit or (pursuit.mode or 0) == 0 then
      -- Mode -1 is an arrest in progress, any other non-zero mode an ongoing chase: either one already counts.
      local responderId = police.getNearestPoliceVehicle(vehId, false, true)
      police.setPursuitMode(1, vehId, responderId and {responderId} or nil)
    end
    sting.pursuing = vehId
    save()
    notify("Unmarked units are on you. Lose them, or the stolen car is seized and the theft fine charged.")
    return true
  end

  local function springSting(case)
    local now = gameTime()
    case.phase, case.listing = "stored", nil
    case.identity = nil
    -- The next identity change issues a plate from a new series; the burned one is known.
    case.identityRevision = (case.identityRevision or 0) + 1
    -- The theft report now describes the car as the buyer saw it.
    case.paint = recordColor(case.inventoryId) or case.paint
    case.heatHotUntil, case.heatWarmUntil = now + heatHotSeconds, now + heatHotSeconds + heatWarmSeconds
    case.reportAt = math.min(case.reportAt or now, now)
    case.reported, case.recognizedAt, case.sightedPatrol = true, nil, nil
    session.state.sting = {serial = case.serial, untilAt = now + stingSeconds}
    session.lastResult = {kind = "sting"}
    save()
    notify("The buyer was an undercover cop. The deal is off and the car's new plate is burned.")
    if not startStingPursuit() then
      notify("Undercover units are looking for you. The next time you drive, expect a chase.")
    end
    return "sting"
  end

  -- Runs the undercover operation every second: chase the next vehicle the player drives, and end the
  -- operation when the stung car is gone, when a chase fades out without an evade or arrest event, or when
  -- nobody was chased before its time ran out.
  local function updateSting(now)
    local sting = session.state.sting
    if not sting then return end
    local function finish(message)
      session.state.sting = nil
      save()
      if message then notify(message) end
    end
    if not findCase(sting.serial) then return finish() end
    if sting.pursuing then
      local police = overhaul_integration_services_police
      local pursuit = police and police.getPursuitData(sting.pursuing)
      if pursuit and (pursuit.mode or 0) ~= 0 then
        sting.quietSince = nil
      else
        -- Evade and arrest arrive through onPursuitAction; a chase that just stops is a lost trail.
        sting.quietSince = sting.quietSince or now
        if now - sting.quietSince >= 5 then
          finish("The undercover units lost your trail. The car is yours, but it needs a new identity and a new colour.")
        end
      end
      return
    end
    if now >= sting.untilAt then
      return finish("The undercover operation lost track of you. Crews will work on the car again.")
    end
    startStingPursuit()
  end

  function M.onPursuitAction(id, action)
    if not session.state then return end
    -- The undercover chase is on whatever the player was driving, usually not the stolen car itself.
    local sting = session.state.sting
    if sting and sting.pursuing == id and (action == "evade" or action == "arrest") then
      session.state.sting = nil
      if action == "evade" then
        -- When the chased car is the stolen one, the case handler below counts the evasion.
        if not caseForVehicle(id) then count("evaded") end
        grantXp(15, "Undercover sting escaped")
        notify("You lost the undercover units. The car is still yours, but it needs a new identity and a new colour.")
        save()
      else
        local serial = sting.serial
        save()
        -- Defer like the arrest below, until RLS has finished its own arrest handler.
        core_jobsystem.create(function(job)
          job.sleep(0.1)
          local case = session.state and findCase(serial)
          if case then seize("The undercover sting ended in your arrest.", case) end
        end, 1)
      end
    end
    local arrestedCase = caseForVehicle(id)
    if not arrestedCase then return end
    if action == "evade" then
      arrestedCase.patrolCooldownUntil = gameTime() + 45
      arrestedCase.evades = (arrestedCase.evades or 0) + 1
      count("evaded")
      if arrestedCase.evades <= 3 then grantXp(10, "Police evaded in a stolen vehicle") end
      save()
    elseif action == "arrest" then
      -- Defer object removal until RLS has finished its own arrest handler.
      core_jobsystem.create(function(job)
        job.sleep(0.1)
        -- A fully disguised car caught for an ordinary offence is just a car: RLS charges its normal fine.
        if session.state and findCase(arrestedCase.serial) == arrestedCase and not disguised(arrestedCase)
          and caseVehicleId(arrestedCase) == id then
          seize("Police identified the stolen vehicle.", arrestedCase)
        end
      end, 1)
    end
  end

  -- Every second for each case: report the theft and start the police on the car. Heat sets how close a
  -- patrol has to be to spot it; a carjacked car (case.immediate) is called in at once.
  local function updatePatrol(case, now)
    -- After the identity change only an unrepainted car can still be matched to the theft report.
    if disguised(case) then return end
    local id = case.inventoryId and inventory().getVehicleIdFromInventoryId(case.inventoryId) or session.liveId
    local vehicle = id and getObjectByID(id)
    if not vehicle then
      if case.phase == "transit" then session.liveId = nil end
      return
    end
    if now < math.max(case.reportAt, case.patrolCooldownUntil or 0) or be:getPlayerVehicleID(0) ~= id then return end
    if not case.reported then
      case.reported = true
      notify("The vehicle has been reported stolen.")
    end
    local police = overhaul_integration_services_police
    local pursuit = police.getPursuitData(id)
    -- Only start from a clean state: mode -1 is an arrest in progress and must not be overridden.
    if not pursuit or (pursuit.mode or 0) ~= 0 then return end
    -- A case's pursuit starts at its wanted level: 1 for an ordinary car, taxiTheft.wantedLevel for a stolen cab.
    -- RLS's top level (3, roadblocks) goes to every unit, as RLS does when a pursuit climbs to it on its own;
    -- a lower level goes to the unit that responded or spotted the car.
    local function startPursuit(unitId)
      local level = case.wanted or 1
      police.setPursuitMode(level, id, (level < 3 and unitId) and {unitId} or nil)
    end
    if case.immediate then
      -- Carjacking: the driver calls it in, so the nearest unit responds without having seen the car.
      -- One-shot: once evaded, the case falls back to the sighting rule below.
      case.immediate = nil
      startPursuit(police.getNearestPoliceVehicle(id, false, true))
      save()
      return
    end
    -- Heat decides how close a patrol has to be to spot the car; a cooled report also halves the chance
    -- that a patrol recognizes the original paint under a new plate.
    local stage = heatStatus(case, now).stage
    local patrolId = police.getNearestPoliceVehicle(id, true, true)
    local patrol = patrolId and getObjectByID(patrolId)
    if patrol and distance(patrol, vehicle) <= sightRanges[stage] then
      if not case.identity then
        case.heatHotUntil, case.heatWarmUntil = now + heatHotSeconds, now + heatHotSeconds + heatWarmSeconds
        notify("A patrol spotted the stolen car. It's hot again; keep it out of sight to cool it down.")
        save()
        startPursuit(patrolId)
      elseif case.sightedPatrol ~= patrolId then
        -- New plate, reported paint: each patrol gets one look at the car.
        case.sightedPatrol = patrolId
        if math.random() < paintRecognitionChance() * (stage == "cold" and 0.5 or 1) then
          case.heatHotUntil, case.heatWarmUntil = now + heatHotSeconds, now + heatHotSeconds + heatWarmSeconds
          case.recognizedAt = now
          notify("A patrol recognized the stolen vehicle by its original paint. It's hot again; repaint it to break the link.")
          startPursuit(patrolId)
        end
        save()
      end
    end
  end

  ctx.springSting = springSting
  ctx.updatePatrol = updatePatrol
  ctx.updateSting = updateSting

  return function()
    caseForVehicle = ctx.caseForVehicle
    caseVehicleId = ctx.caseVehicleId
    count = ctx.count
    disguised = ctx.disguised
    distance = ctx.distance
    findCase = ctx.findCase
    gameTime = ctx.gameTime
    grantXp = ctx.grantXp
    heatStatus = ctx.heatStatus
    inventory = ctx.inventory
    notify = ctx.notify
    paintRecognitionChance = ctx.paintRecognitionChance
    recordColor = ctx.recordColor
    save = ctx.save
    seize = ctx.seize
  end
end
