-- Open theft cases: lookups, paint and heat of a case, seizure, investigations and leaving a car
-- behind. A profile can hold several cases (state.cases); see vehicleCase below.

return function(ctx)
  local session = ctx.session
  local config = ctx.config
  local abandonDistance, heatHotSeconds, heatMultipliers, heatWarmSeconds =
    config.abandonDistance, config.heatHotSeconds, config.heatMultipliers, config.heatWarmSeconds
  -- From the other parts; bound by the function this file returns once every part is installed.
  local charge, distance, exitVehicle, fineFor, gameTime, inventory, money, notify, perk, save, walkingPlayer

  -- A profile can hold several open cases (state.cases). At most one is "transit": the car you are
  -- carrying, tracked by liveId. Every other case is a stored car that follows its inventory id.
  local function vehicleCase(id)
    id = tonumber(id)
    if not id then return end
    for _, case in ipairs(session.state and session.state.cases or {}) do
      if case.inventoryId == id then
        local record = inventory().getVehicles()[id]
        if record and record.rlsTheftCase == case.serial then return case end
      end
    end
  end

  local function transitCase()
    for _, case in ipairs(session.state and session.state.cases or {}) do
      if case.phase == "transit" then return case end
    end
  end

  local function findCase(serial)
    for _, case in ipairs(session.state and session.state.cases or {}) do
      if case.serial == serial then return case end
    end
  end

  local function removeCase(case)
    for index, other in ipairs(session.state.cases) do
      if other == case then
        table.remove(session.state.cases, index)
        break
      end
    end
    -- liveId only ever belongs to the transit case; once none is left it must not point at a stale object.
    if not transitCase() then session.liveId = nil end
  end

  -- The live object of a case: the carried car for a transit case, the garage car otherwise.
  local function caseVehicleId(case)
    if case.phase == "transit" then return session.liveId end
    return case.inventoryId and inventory().getVehicleIdFromInventoryId(case.inventoryId) or nil
  end

  local function caseForVehicle(vehId)
    for _, case in ipairs(session.state and session.state.cases or {}) do
      if vehId and caseVehicleId(case) == vehId then return case end
    end
  end

  -- Each extra open case keeps more police attention on you.
  local function heat()
    return 1 + 0.15 * math.max(0, #(session.state and session.state.cases or {}) - 1)
  end

  -- Paint as a {r, g, b} triple. RLS repaints write the inventory record's config.paints
  -- (career/parts/painting.lua), so that record is the source of truth for the current colour.
  local function baseColor(paint)
    local c = type(paint) == "table" and paint.baseColor
    if type(c) == "table" and tonumber(c[1]) and tonumber(c[2]) and tonumber(c[3]) then
      return {tonumber(c[1]), tonumber(c[2]), tonumber(c[3])}
    end
  end

  local function recordColor(inventoryId)
    local record = inventory().getVehicles()[inventoryId]
    local paints = record and record.config and record.config.paints
    return type(paints) == "table" and baseColor(paints[1]) or nil
  end

  -- true: repainted since the theft; false: still the reported colour; nil: unknown (cases from older versions).
  local function repainted(case)
    local current = case.paint and case.inventoryId and recordColor(case.inventoryId)
    if not current then return nil end
    local difference = 0
    for i = 1, 3 do difference = difference + math.abs(current[i] - case.paint[i]) end
    return difference > 0.1
  end

  -- A new identity hides the plate, not the paint described in the theft report.
  -- Base 30% per new patrol that sees the car and 20% at the underground handover; Vehicle Theft lowers both.
  local function paintRecognitionChance() return math.min(0.9, perk("paintRecognition", 0.3) * heat()) end
  local function paintStingChance() return math.min(0.9, perk("paintSting", 0.2) * heat()) end
  local function caseLimit() return perk("caseLimit", 2) end

  local function seize(reason, case)
    if not case then return false end
    local id = case.inventoryId
    if id and vehicleCase(id) then
      exitVehicle(inventory().getVehicleIdFromInventoryId(id))
      if inventory().removeVehicle(id) == false then
        case.seizure = reason
        save()
        notify("Sale canceled. The vehicle is pending seizure.")
        return false
      end
    elseif case.phase == "transit" and session.liveId then
      local vehicle = getObjectByID(session.liveId)
      if vehicle then
        exitVehicle(session.liveId)
        vehicle:delete()
      end
    end
    local amount = fineFor(case)
    charge(amount, reason, "fine", true)
    removeCase(case)
    save()
    notify(reason .. " Vehicle seized. Fine: " .. money(amount))
    return false
  end

  -- True once the stolen car has a new plate and a new colour: nothing links it to the theft report any more.
  local function disguised(case)
    return case.identity ~= nil and repainted(case) ~= false
  end

  -- Heat cools in two clear stages. It sets what buyers and the chop shop pay and how close a patrol has to
  -- get to spot the car (sightRanges). A new plate helps immediately; a new plate and paint break the link.
  local function heatStatus(case, now)
    now = now or gameTime()
    local paintChanged = repainted(case)
    if case.identity and paintChanged ~= false then
      return {stage = "cold", label = "Cold", remaining = 0, multiplier = heatMultipliers.cold,
        detail = "New plate and paint: patrols can no longer match this car to the theft report."}
    end

    local stage, untilAt, detail
    if now < (case.heatHotUntil or (case.reportAt or now) + heatHotSeconds) then
      stage, untilAt = "hot", case.heatHotUntil
      detail = now < (case.reportAt or 0)
        and "The theft report is still pending, but buyers already price the car as hot."
        or "Fresh theft report. Buyers pay less and patrols spot the car from far away."
    elseif now < (case.heatWarmUntil or (case.reportAt or now) + heatHotSeconds + heatWarmSeconds) then
      stage, untilAt = "warm", case.heatWarmUntil
      detail = "Attention is fading: patrols have to get closer to spot the car. Keep it out of sight until it cools for the full value."
    else
      stage, untilAt = "cold", nil
      detail = "The theft report has cooled. Buyers pay the full underground rate and patrols only notice the car up close."
    end

    -- Changing only the plate makes the car less exposed, but its original paint is still identifiable.
    -- A patrol that recognizes that paint after the identity change makes the car fully hot again.
    local recognized = case.recognizedAt and now < case.recognizedAt + heatHotSeconds
    if case.identity and paintChanged == false and stage == "hot" and not recognized then
      stage, untilAt = "warm", case.heatWarmUntil
      detail = "The new plate helps, but the original paint still matches the theft report. Repaint it to break the link."
    end
    return {stage = stage, label = stage == "hot" and "Hot" or stage == "warm" and "Warm" or "Cold",
      remaining = untilAt and math.max(0, untilAt - now) or 0, multiplier = heatMultipliers[stage], detail = detail}
  end

  -- A dealership whose test-drive car was taken knows who took it: whatever happens to the car later
  -- (sold, stripped or left behind), its investigation ends with a fine.
  local function openInvestigation(case)
    if case.source ~= "testDrive" then return false end
    session.state.citations[#session.state.citations + 1] = {due = gameTime() + 150, amount = fineFor(case)}
    return true
  end

  -- True while an undercover operation is after this case's car (state.sting, see "Undercover buyers").
  -- No workshop or chop shop touches such a car until the player has lost the police or the operation ends.
  local function underSting(case)
    return session.state and session.state.sting ~= nil and case ~= nil and session.state.sting.serial == case.serial
  end

  local function currentValue(case)
    -- A car stripped without a garage slot has no inventory record; its value was read when it was taken.
    if not case.inventoryId then return math.max(0, tonumber(case.scrapValue) or 0) end
    return math.max(0, tonumber(overhaul_career_market_valueCalculator.getInventoryVehicleSellValue(case.inventoryId)) or 0)
  end

  -- Expenses recorded for this car (identity fee and RLS repaint charges) and whether the total is
  -- incomplete: a car whose identity was changed, or that was repainted, before this tracking existed has
  -- no record, so it is flagged as partial instead of showing a falsely precise figure. Police fines are
  -- not trade expenses and are left out.
  local function expensesFor(case)
    local spent = case.expenses or {}
    local identity, paint = tonumber(spent.identity), tonumber(spent.paint)
    local partial = (case.identity ~= nil and identity == nil) or (repainted(case) == true and paint == nil)
    return (identity or 0) + (paint or 0), partial, identity or 0, paint or 0
  end

  -- Abandoning: walk away from a stolen car you have not stored. Beyond this distance, with no pursuit on
  -- you, the car is left behind: no theft fine, but also no payout and no XP (that is paid on storage).
  -- A test-drive car is the exception: the dealership knows who took it and still opens an investigation.

  local function checkAbandon(case)
    if case.phase ~= "transit" or not session.liveId or be:getPlayerVehicleID(0) == session.liveId then return false end
    local vehicle = getObjectByID(session.liveId)
    local player = walkingPlayer()
    if not vehicle or not player or distance(vehicle, player) < abandonDistance then return false end
    local pursuit = overhaul_integration_services_police.getPursuitData(session.liveId)
    if pursuit and (pursuit.mode or 0) ~= 0 then return false end
    local reported = case.reported or gameTime() >= (case.reportAt or 0)
    vehicle:delete()
    local investigated = openInvestigation(case)
    removeCase(case)
    save()
    if investigated then
      notify("You left the stolen car behind. The dealership knows who took it and has opened an investigation.")
    else
      notify(reported and "You left the stolen car behind. Police will tow it; there is no fine."
        or "You left the stolen car behind. Nobody has noticed it yet; there is no fine.")
    end
    return true
  end

  -- First check of every case each second: settle a case whose car is already gone. Returns true when the
  -- case was handled this tick (seized, fined, or still waiting for a seizure that RLS has to allow first).
  local function settleLostCase(case)
    if case.seizure then
      if not case.inventoryId or not vehicleCase(case.inventoryId)
        or overhaul_career_logistics_general.canRemoveLogisticsVehicle(case.inventoryId) then
        seize(case.seizure, case)
      end
      return true
    end
    if case.inventoryId and not vehicleCase(case.inventoryId) then
      -- The inventory record went away outside the mod's guarded sale paths: the car is gone, the theft stands.
      local amount = fineFor(case)
      charge(amount, "Missing stolen vehicle", "fine", true)
      removeCase(case)
      save()
      notify("A stolen vehicle left your garage outside the underground. The theft is on record. Fine: " .. money(amount))
      return true
    end
    if case.phase == "transit" and not session.liveId then
      removeCase(case)
      charge(fineFor(case), "Unresolved vehicle theft", "fine", true)
      save()
      notify("The unstored vehicle was recovered and a theft fine was charged.")
      return true
    end
    return false
  end

  -- Charges each dealership test-drive investigation once it is due (see openInvestigation).
  local function updateCitations(now)
    for i = #session.state.citations, 1, -1 do
      local citation = session.state.citations[i]
      if now >= citation.due then
        table.remove(session.state.citations, i)
        charge(citation.amount, "Dealership test-drive investigation", "fine", true)
        notify("Test-drive investigation closed. Fine: " .. money(citation.amount))
        save()
      end
    end
  end

  ctx.baseColor = baseColor
  ctx.caseForVehicle = caseForVehicle
  ctx.caseLimit = caseLimit
  ctx.caseVehicleId = caseVehicleId
  ctx.checkAbandon = checkAbandon
  ctx.currentValue = currentValue
  ctx.disguised = disguised
  ctx.expensesFor = expensesFor
  ctx.findCase = findCase
  ctx.heatStatus = heatStatus
  ctx.openInvestigation = openInvestigation
  ctx.paintRecognitionChance = paintRecognitionChance
  ctx.paintStingChance = paintStingChance
  ctx.recordColor = recordColor
  ctx.removeCase = removeCase
  ctx.repainted = repainted
  ctx.seize = seize
  ctx.settleLostCase = settleLostCase
  ctx.transitCase = transitCase
  ctx.underSting = underSting
  ctx.updateCitations = updateCitations
  ctx.vehicleCase = vehicleCase

  return function()
    charge = ctx.charge
    distance = ctx.distance
    exitVehicle = ctx.exitVehicle
    fineFor = ctx.fineFor
    gameTime = ctx.gameTime
    inventory = ctx.inventory
    money = ctx.money
    notify = ctx.notify
    perk = ctx.perk
    save = ctx.save
    walkingPlayer = ctx.walkingPlayer
  end
end
