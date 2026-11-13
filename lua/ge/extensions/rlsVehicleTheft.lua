local M = {}
local saveFile = "/career/rlsVehicleTheft.json"
local state, profile, attempted, liveId, patrolCheck
local bindings = {}
local ignition, ignitionToken, ignitionCooldown = nil, 0, 0
-- Underground app session state (not saved): the open negotiation, whether the app is showing, last sale.
local negotiation, appOpen, lastResult
-- The case the Underground app is showing (not saved).
local selectedSerial
local appTick = 0
local ignitionStages, ignitionSeconds = 3, 25
-- Per-stage marker speed (track units/s on a 15-unit track) and target half-width.
local ignitionSpeeds = {6, 7.5, 9}
local ignitionHalfWidths = {2.1, 1.9, 1.7}
-- The UI shows the marker slightly behind the simulation (30 Hz updates + UI bridge latency),
-- so a lock also counts if the marker was in the zone within this many seconds before the click.
local ignitionGrace = 0.16
local ignitionMissPenalty, ignitionFailCooldown = 4, 8
local ignitionRoute = "rls-theft-ignition"
-- Misses of an abandoned bypass, per vehicle (not saved): the alarm a miss trips stays tripped on a retry.
local bypassMisses = {}
local starter
local rules = {
  street = {fine = 0.34, minimum = 3000},
  inspection = {fine = 0.42, minimum = 4500, reputation = 120},
  testDrive = {fine = 0.50, minimum = 5500, reputation = 220},
}
local heatHotSeconds, heatWarmSeconds = 120, 240
-- Share of the car's value the underground pays at each heat stage (before the fenceValue perk).
local heatMultipliers = {hot = 0.54, warm = 0.58, cold = 0.61}
-- How close a patrol has to be to spot a reported car at each heat stage, in metres.
local sightRanges = {hot = 160, warm = 100, cold = 60}
-- Share of underground buyers who are undercover police, by the car's heat when the offer comes in.
local undercoverChances = {hot = 0.04, warm = 0.03, cold = 0.02}
-- How long an undercover operation keeps looking for a seller who has not been chased yet (play time).
local stingSeconds = 600

-- Play time in seconds. Every saved timer (reports, heat, workshop jobs, offers, bans, investigations) is
-- measured against it. It runs on real time while the career is loaded, so a paused simulation or an open
-- phone does not freeze the countdowns, but it stops while the game is closed.
local function gameTime()
  return state and state.clock or 0
end

-- The player's current binding for the take/store action, so messages never name a stale key.
local function keyLabel()
  local control = core_input_bindings and core_input_bindings.getControlForAction
    and core_input_bindings.getControlForAction("rlsVehicleTheftAttempt")
  if type(control) ~= "string" or control == "" then return "Ctrl+Shift+J" end
  local parts = {}
  for word in control:gmatch("[^%s%+]+") do
    local button = word:match("^button(%d+)$")
    parts[#parts + 1] = button and ("Mouse " .. (tonumber(button) + 1))
      or (#word <= 2 and word:upper() or (word:sub(1, 1):upper() .. word:sub(2)))
  end
  return table.concat(parts, "+")
end

local function notify(message)
  ui_message(message, 7, "rlsVehicleTheft")
end

local function money(amount)
  return string.format("$%d", amount)
end

local function save()
  overhaul_career_saveSystem.saveCurrent(nil, {force = true})
end

local function inventory()
  return overhaul_career_garage_inventory
end

local function load()
  if not overhaul_career_career or not overhaul_career_career.isActive()
    or not overhaul_career_saveSystem or not inventory() then return false end
  local name, path = overhaul_career_saveSystem.getCurrentSaveSlot()
  if not name or not path then return false end
  if name ~= profile then
    profile = name
    state = jsonReadFile(path .. saveFile) or {}
    state.bans = state.bans or {}
    state.citations = state.citations or {}
    state.serial = state.serial or 0
    state.cases = state.cases or {}
    -- Before 0.9 timers were wall-clock (os.time); starting the play-time clock there keeps them valid.
    state.clock = tonumber(state.clock) or os.time()
    -- A saved undercover operation survives the reload, but the vehicle it was chasing does not.
    if state.sting then state.sting.pursuing = nil end
    -- Before 0.8 a profile held a single case in state.case; it becomes the first entry of the list.
    if state.case then
      table.insert(state.cases, state.case)
      state.case = nil
    end
    for _, case in ipairs(state.cases) do
      -- Before 0.6 a single offer was requested at the garage computer; those cases go back to "ready"
      -- so the vehicle can be listed in the Underground phone app.
      if case.phase == "offer" then case.phase, case.offer, case.expiresAt = "ready", nil, nil end
      -- Older cases used one six-minute hot window tied directly to the expected report time.
      -- Preserve that window while splitting it into a hot and warm stage.
      local reportAt = case.reportAt or gameTime()
      case.heatHotUntil = case.heatHotUntil or (reportAt + heatHotSeconds)
      case.heatWarmUntil = case.heatWarmUntil or (reportAt + heatHotSeconds + heatWarmSeconds)
    end
    attempted, liveId, patrolCheck = nil, nil, 0
    negotiation, lastResult, selectedSerial = nil, nil, nil
  end
  return true
end

local function charge(amount, label, category, allowDebt)
  return overhaul_career_economy_payment.pay({money = {amount = amount, canBeNegative = allowDebt}},
    {label = label, category = category, tags = {"vehicleTheft"}})
end

local function fineFor(case)
  local rule = rules[case.source]
  return math.max(rule.minimum, math.floor((case.value or 0) * rule.fine))
end

-- Progression ------------------------------------------------------------------------------------
-- Vehicle Theft is an RLS career skill (gameplay/overhaul/domains/careerSkills/skills/vehicleTheft/info.json).
-- XP is the player attribute below; RLS shows levels, level-up celebrations and per-level milestones for it.
-- Perks are step functions of the level and match the unlock cards in that file.

local skillKey = "careerSkills-vehicleTheft"
local skillFile = "/gameplay/overhaul/domains/careerSkills/skills/vehicleTheft/info.json"
local skillCurve

local perkTiers = {
  ignitionWidth = {{3, 1.10}, {10, 1.20}, {25, 1.30}},
  missPenalty = {{10, 3}},
  parkedWait = {{5, 3}},
  fenceValue = {{8, 1.03}, {18, 1.06}, {30, 1.10}, {45, 1.12}, {50, 1.15}},
  identityFee = {{12, 0.9}, {25, 0.8}, {40, 0.7}},
  quietEntry = {{15, 1.25}},
  identityTime = {{20, 120}, {40, 90}},
  offerPace = {{30, 0.85}},
  paintRecognition = {{35, 0.22}, {50, 0.15}},
  paintSting = {{35, 0.15}, {50, 0.10}},
  caseLimit = {{10, 3}, {25, 4}},
}

local function skillXp()
  local attributes = overhaul_career_economy_playerAttributes
  return attributes and tonumber(attributes.getAttributeValue(skillKey)) or 0
end

local function theftLevel()
  if not skillCurve then
    local data = jsonReadFile(skillFile)
    skillCurve = {}
    for _, level in ipairs(data and data.levels or {}) do table.insert(skillCurve, level.requiredValue or 0) end
  end
  local xp, level = skillXp(), 1
  for index, required in ipairs(skillCurve) do
    if xp >= required then level = index end
  end
  return level
end

-- Level, XP and the XP span of the current level, for the skill card in the Underground app.
local function skillProgress()
  local level, xp = theftLevel(), skillXp()
  local from, to = skillCurve[level] or 0, skillCurve[level + 1]
  return {level = level, xp = math.floor(xp), from = from, to = to, max = to == nil}
end

local function perk(key, default)
  local level, value = theftLevel(), default
  for _, tier in ipairs(perkTiers[key]) do
    if level >= tier[1] then value = tier[2] end
  end
  return value
end

-- Counters behind the theft milestones, saved with the mod's career data.
local function stats()
  state.stats = state.stats or {}
  local s = state.stats
  s.stolen, s.carjacked, s.cleanBypass = s.stolen or 0, s.carjacked or 0, s.cleanBypass or 0
  s.sold, s.revenue, s.evaded = s.sold or 0, s.revenue or 0, s.evaded or 0
  s.chopped = s.chopped or 0
  return s
end

local theftMilestones = {}

-- Notifies RLS when a theft milestone tier is reached (same pattern as RLS's speedTraps milestones).
local function checkTheftMilestones()
  local milestones = overhaul_career_progression_milestones_milestones
  local general = milestones and milestones.saveData and milestones.saveData.general
  if not general then return end
  for _, config in ipairs(theftMilestones) do
    local save = general[config.id]
    while save and save.notificationStep < config.maxStep do
      local target = config.getTarget(save.notificationStep + 1)
      if not target or config.getValue() < target then break end
      milestones.milestoneReached(config.getLabel(save.notificationStep + 1))
      save.notificationStep = save.notificationStep + 1
    end
  end
end

local function count(statName, amount)
  local s = stats()
  s[statName] = s[statName] + (amount or 1)
  checkTheftMilestones()
end

-- XP per step of a theft. A full cycle (take, store, new identity, sell) earns roughly 60-100 XP,
-- about what a few RLS repo jobs pay, so level 5 takes ~15-20 thefts and level 10 ~60.
local function grantXp(amount, label)
  amount = math.floor(amount)
  local attributes = overhaul_career_economy_playerAttributes
  if amount <= 0 or not attributes then return end
  attributes.addAttributes({[skillKey] = amount},
    {label = string.format("%s (+%d XP)", label, amount), tags = {"vehicleTheft", "gameplay"}})
  ui_message(string.format("Vehicle Theft +%d XP", amount), 3, "rlsVehicleTheftXp")
end

-- Milestones -------------------------------------------------------------------------------------

-- A tiered counter milestone over one stats() field. reward is the money per tier, scaled like RLS's
-- minorLinear ($100 x tier) and majorLinear ($250 x tier). currency shows targets as money.
local function counterMilestone(id, label, description, icon, statName, targets, reward, currency)
  local function show(value) return currency and money(value) or tostring(value) end
  return {
    id = id, filter = {general = true}, type = "stat", icon = icon,
    color = "var(--bng-orange-500-rgb)", maxStep = #targets,
    getValue = function() return load() and stats()[statName] or 0 end,
    getLabel = function() return label end,
    getDescription = function(step, _, target)
      return string.format(description, show(target or targets[math.min(math.max(step, 1), #targets)]))
    end,
    getProgressLabel = function(_, current, target)
      if currency then return string.format("%s / %s", money(current), money(target)) end
      return {txt = "ui.career.milestones.progress.count", context = {current = current, target = target}}
    end,
    getTarget = function(step) return step == 0 and 0 or targets[step] end,
    getRewards = function(step) return {{attributeKey = "money", rewardAmount = reward * (step + 1)}} end,
  }
end

-- RLS collects general milestones from every loaded extension (career/progression/milestones/general.lua).
function M.onOverhaulGeneralMilestonesCollect(list)
  local milestones = overhaul_career_progression_milestones_milestones
  if not milestones then return end
  milestones.saveData.general = milestones.saveData.general or {}
  theftMilestones = {
    counterMilestone("rlsTheftStolen", "Car Thief", "Steal %s vehicles.", "keys1", "stolen", {1, 5, 15, 30, 60, 100}, 100),
    counterMilestone("rlsTheftCarjacked", "Carjacker", "Take %s cars from their drivers.", "car", "carjacked", {1, 5, 15, 30}, 100),
    counterMilestone("rlsTheftCleanBypass", "Clean Hands", "Bypass %s ignitions without missing a signal.", "keys1", "cleanBypass", {1, 10, 25, 50}, 100),
    counterMilestone("rlsTheftEvaded", "Ghost Driver", "Lose the police %s times in a stolen vehicle.", "roadblockL", "evaded", {1, 5, 15, 30}, 100),
    counterMilestone("rlsTheftSold", "Fence", "Sell %s vehicles to underground buyers.", "beamCurrency", "sold", {1, 5, 15, 30, 60}, 250),
    counterMilestone("rlsTheftRevenue", "Underground Earnings", "Earn %s from underground sales.", "beamCurrency", "revenue",
      {10000, 50000, 150000, 400000, 1000000}, 250, true),
  }
  for _, milestone in ipairs(theftMilestones) do
    milestones.saveData.general[milestone.id] = milestones.saveData.general[milestone.id] or {claimedStep = 0, notificationStep = 0}
    table.insert(list, milestone)
  end
end

-- RLS's Skills page lists a fixed set of careerSkills (career/progression/skillsPage.lua), so add ours to
-- the root page's entries. Opening the entry works without help: skill pages are built from any branch id.
local function decorateSkillsPage(original)
  return function(pathId, ...)
    local data = original(pathId, ...)
    local root = pathId == nil or pathId == "" or pathId == "undefined" or pathId == "careerSkills"
    if root and type(data) == "table" and type(data.branches) == "table" then
      for _, entry in ipairs(data.branches) do
        if entry.id == skillKey then return data end
      end
      table.insert(data.branches, {id = skillKey, target = "skillPage", isSkill = true,
        description = "Take cars off the street, give them a new identity and sell them to the underground."})
    end
    return data
  end
end

-- A profile can hold several open cases (state.cases). At most one is "transit": the car you are
-- carrying, tracked by liveId. Every other case is a stored car that follows its inventory id.
local function vehicleCase(id)
  id = tonumber(id)
  if not id then return end
  for _, case in ipairs(state and state.cases or {}) do
    if case.inventoryId == id then
      local record = inventory().getVehicles()[id]
      if record and record.rlsTheftCase == case.serial then return case end
    end
  end
end

local function transitCase()
  for _, case in ipairs(state and state.cases or {}) do
    if case.phase == "transit" then return case end
  end
end

local function findCase(serial)
  for _, case in ipairs(state and state.cases or {}) do
    if case.serial == serial then return case end
  end
end

local function removeCase(case)
  for index, other in ipairs(state.cases) do
    if other == case then
      table.remove(state.cases, index)
      break
    end
  end
  -- liveId only ever belongs to the transit case; once none is left it must not point at a stale object.
  if not transitCase() then liveId = nil end
end

-- The live object of a case: the carried car for a transit case, the garage car otherwise.
local function caseVehicleId(case)
  if case.phase == "transit" then return liveId end
  return case.inventoryId and inventory().getVehicleIdFromInventoryId(case.inventoryId) or nil
end

local function caseForVehicle(vehId)
  for _, case in ipairs(state and state.cases or {}) do
    if vehId and caseVehicleId(case) == vehId then return case end
  end
end

-- Each extra open case keeps more police attention on you.
local function heat()
  return 1 + 0.15 * math.max(0, #(state and state.cases or {}) - 1)
end

-- RLS leaves the arrested player seated; deleting a vehicle with the player inside strands them.
-- Mirror RLS's own removal path and put the player on foot first.
local function exitVehicle(vehId)
  if vehId and be:getPlayerVehicleID(0) == vehId and gameplay_walk and not gameplay_walk.isWalking() then
    gameplay_walk.setWalkingMode(true, nil, nil, true)
  end
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
  elseif case.phase == "transit" and liveId then
    local vehicle = getObjectByID(liveId)
    if vehicle then
      exitVehicle(liveId)
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

local function rejectTransfer(id)
  if not load() then return nil end
  local case = vehicleCase(id)
  if not case then return nil end
  local reason = case.identity and "Registration check failed during title transfer."
    or "The title transfer flagged the vehicle as stolen."
  seize(reason, case)
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
  state.citations[#state.citations + 1] = {due = gameTime() + 150, amount = fineFor(case)}
  return true
end

-- True while an undercover operation is after this case's car (state.sting, see "Undercover buyers").
-- No workshop or chop shop touches such a car until the player has lost the police or the operation ends.
local function underSting(case)
  return state and state.sting ~= nil and case ~= nil and state.sting.serial == case.serial
end

-- RLS speed and red-light cameras bill whoever owns the inventory record. While the stolen car still wears
-- its original plate, the registered keeper is the previous owner, so the camera fine is not charged to the thief.
local cameraFineLabels = {
  ["ui.career.attributeLog.fineSpeeding"] = true,
  ["ui.career.attributeLog.fineRedLight"] = true,
}

local function wearsOriginalPlate()
  if not load() then return false end
  local case = caseForVehicle(be:getPlayerVehicleID(0))
  return case ~= nil and not case.identity
end

local function bind(owner, key, decorate)
  if not owner or type(owner[key]) ~= "function" then return end
  local existing = bindings[key]
  if existing and existing.owner == owner and owner[key] == existing.wrapper then return end
  local original = owner[key]
  local wrapper = decorate(original)
  owner[key] = wrapper
  bindings[key] = {owner = owner, original = original, wrapper = wrapper}
end

local function guardTransfer(original)
  return function(id, ...)
    if rejectTransfer(id) == false then return false end
    return original(id, ...)
  end
end

local function inspectedDealer()
  local inspection = overhaul_career_market_inspectVehicle
  local shop = overhaul_career_market_vehicleShopping
  local info = inspection and inspection.getSpawnedVehicleInfo()
  local listing = info and shop and shop.getVehicleInfoByShopId(info.shopId)
  if not listing or not listing.sellerId then return end
  local seller = tostring(listing.sellerId)
  local dealer = overhaul_world_facilities.getFacility("dealership", seller, true)
  if dealer then return info, seller, listing, dealer end
end

local function bindRls()
  bind(inventory(), "sellVehicle", guardTransfer)
  bind(inventory(), "sellVehicleFromInventory", guardTransfer)
  bind(overhaul_career_market_auction_auction, "listVehicleForNextAnythingGoesAuction", guardTransfer)
  bind(inventory(), "openMenu", function(original)
    return function(buttons, title, ...)
      if title == "Trade-In" and buttons and buttons[1] and type(buttons[1].callback) == "function" then
        buttons[1].callback = guardTransfer(buttons[1].callback)
      end
      return original(buttons, title, ...)
    end
  end)
  bind(overhaul_career_economy_payment, "pay", function(original)
    return function(price, reason, ...)
      if type(reason) == "table" and cameraFineLabels[reason.label] and wearsOriginalPlate() then
        notify("Camera fine sent to the vehicle's registered owner.")
        return true
      end
      return original(price, reason, ...)
    end
  end)
  bind(overhaul_career_progression_skillsPage, "getLandingPageData", decorateSkillsPage)
  bind(overhaul_career_market_testDrive, "start", function(original)
    return function(...)
      local _, seller = inspectedDealer()
      if seller and load() and (state.bans[seller] or 0) > gameTime() then
        notify("This dealership has suspended your test-drive privileges.")
        return false
      end
      return original(...)
    end
  end)
end

local function distance(a, b)
  return a:getPosition():distance(b:getPosition())
end

local function walkingPlayer()
  return gameplay_walk.getCurrentUnicycle and gameplay_walk.getCurrentUnicycle() or be:getPlayerVehicle(0)
end

local function accessDistance(vehicle, player)
  local from = player:getPosition()
  local distanceToOrigin = from:distance(vehicle:getPosition())
  local walk = overhaul_avatar_walkEnterVehicle
  if distanceToOrigin <= 9 and walk and walk.getStandPos then
    local stand = walk.getStandPos(vehicle, from)
    if stand then return from:distance(stand) end
  end
  return distanceToOrigin
end

local function parkedCars()
  local parking = overhaul_integration_services_parking
  return parking and parking.getParkedCarsData() or {}
end

-- RLS parks "simple_traffic" props (Type PropParked): their configs have no engine, transmission or
-- drivetrain, so they can never be started or driven. Simplified traffic uses the same model.
-- Stock traffic maps a simple_traffic config to its real model by the config key's first word
-- (bastion_base_parked -> bastion); a stolen prop is swapped for that real model.
-- Returns nil for a normal vehicle, the real model name for a prop, or false if no real model exists.
local realModels = {}
local function realModelFor(vehicle)
  if vehicle:getJBeamFilename() ~= "simple_traffic" then return nil end
  local _, key = path.splitWithoutExt(vehicle.partConfig or "")
  local model = key and string.match(key, "%w+")
  if not model then return false end
  if realModels[model] == nil then
    local models = core_vehicles.getModelList().models
    realModels[model] = models[model] ~= nil
  end
  return realModels[model] and model or false
end

-- Deletes the prop and spawns its real model in the same place, paint and plate. Returns the new vehicle.
local function replaceProp(vehicle)
  local model = realModelFor(vehicle)
  if model == nil then return vehicle end
  if not model then return nil end
  local metallic = vehicle:getMetallicPaintData() or {}
  local options = {
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
local carjackMaxSpeed = 8 -- m/s, about 29 km/h
local carjackReach = 6    -- metres from the car while it is moving
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
  elseif not traffic or not traffic.isAi or traffic.reserved
    or traffic.isTaxi or not traffic.role or traffic.role.name ~= "standard" then
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

-- Traffic top-up. Taking a car out of traffic (removeTraffic) shrinks the traffic for good: the game never
-- refills it, so every theft left one car fewer until only taxis and police (which cannot be stolen) remained.
-- Each stolen traffic car is now owed back to the road and replaced by a freshly spawned traffic car, one at a
-- time. Everything is logged with the "rlsVehicleTheft.traffic" tag in beamng.log.
local trafficTag = "rlsVehicleTheft.traffic"
local trafficOwed, trafficRespawnAt, trafficSpawnPending, trafficFailures = 0, 0, nil, 0
local trafficRespawnGap, trafficSpawnTimeout, trafficMaxOwed = 6, 20, 30
local stolenTraffic = {}

local function trafficSnapshot()
  local standard, special = 0, 0
  for _, entry in pairs(gameplay_traffic.getTrafficData()) do
    if entry.isAi then
      if entry.reserved or entry.isTaxi or (entry.role and entry.role.name ~= "standard") then
        special = special + 1
      else
        standard = standard + 1
      end
    end
  end
  return string.format("state=%s ai=%d active=%d standard=%d special=%d owed=%d", gameplay_traffic.getState(),
    gameplay_traffic.getTrafficAmount(), gameplay_traffic.getTrafficAmount(true), standard, special, trafficOwed)
end

local function trafficLog(event, level)
  local ok, snapshot = pcall(trafficSnapshot)
  log(level or "I", trafficTag, event .. " | " .. (ok and snapshot or ("snapshot failed: " .. tostring(snapshot))))
end

local function resetTrafficTopUp()
  trafficOwed, trafficRespawnAt, trafficSpawnPending, trafficFailures = 0, 0, nil, 0
  stolenTraffic = {}
end

-- Variety: stock group creation weights models by popularity, so the same few cars keep coming up. The
-- replacement is picked from a larger, flatter-weighted sample and prefers a model that is neither on the road
-- right now nor among the last few replacements.
local recentTrafficModels, recentTrafficMax = {}, 6
local varietySample = 16

-- Simplified traffic is one jbeam ("simple_traffic") for every car, so the car's identity is the first word of
-- its config key instead (midsize_v6 -> midsize), the same rule realModelFor uses.
local function trafficIdentity(model, config)
  if model ~= "simple_traffic" then return model end
  -- Not path.splitWithoutExt: it strips every character of a bare config key that has no extension.
  local name = string.match(tostring(config or ""), "([^/\\]+)$") or ""
  return string.match(name, "%w+") or model
end

local function modelsInTraffic()
  local models = {}
  for id in pairs(gameplay_traffic.getTrafficData()) do
    local vehicle = getObjectByID(id)
    if vehicle then
      models[trafficIdentity(vehicle:getJBeamFilename(), vehicle.partConfig)] = true
    end
  end
  return models
end

local function variedTrafficGroup()
  local utils = gameplay_traffic_trafficUtils
  local simple = settings.getValue("trafficSimpleVehicles")
  local params = utils.getBaseGroupParams()
  params.allMods = settings.getValue("trafficAllowMods")
  params.allConfigs = true
  params.modelPopPower = 0.25
  params.configPopPower = simple and 0.25 or 0.5
  if simple then
    params.filters.Type = {proptraffic = 1}
    params.minPop = 0
  else
    params.filters["Config Type"] = {Police = 0, other = 1}
    params.minPop = 10
    if params.allMods and params.filters.Type then params.filters.Type.automation = 1 end
  end
  local sample = core_multiSpawn.createGroup(varietySample, params)
  if not sample or not sample[1] then sample = utils.createTrafficGroup(varietySample) end
  if not sample or not sample[1] then error("empty traffic group") end
  local onRoad, pick = modelsInTraffic(), nil
  local recent = {}
  for _, identity in ipairs(recentTrafficModels) do recent[identity] = true end
  for _, entry in ipairs(sample) do
    local identity = entry.model and trafficIdentity(entry.model, entry.config)
    if identity and not onRoad[identity] and not recent[identity] then pick = entry break end
  end
  if not pick then
    for _, entry in ipairs(sample) do
      local identity = entry.model and trafficIdentity(entry.model, entry.config)
      if identity and not onRoad[identity] then pick = entry break end
    end
  end
  pick = pick or sample[1]
  if pick.model then
    table.insert(recentTrafficModels, trafficIdentity(pick.model, pick.config))
    if #recentTrafficModels > recentTrafficMax then table.remove(recentTrafficModels, 1) end
  end
  local models = {}
  for _, entry in ipairs(sample) do models[entry.model and trafficIdentity(entry.model, entry.config) or "?"] = true end
  local count = 0
  for _ in pairs(models) do count = count + 1 end
  log("I", trafficTag, string.format("replacement model %s %s (sample of %d had %d different models)",
    tostring(pick.model), tostring(pick.config), #sample, count))
  return {pick}
end

-- Called once a second: spawn one replacement car if the road is owed any.
local function updateTrafficTopUp(now)
  if trafficOwed <= 0 then return end
  if trafficSpawnPending then
    if now - trafficSpawnPending < trafficSpawnTimeout then return end
    trafficLog("replacement spawn timed out", "W")
    trafficSpawnPending = nil
  end
  if now < trafficRespawnAt or not gameplay_traffic or gameplay_traffic.getState() ~= "on" then return end
  trafficRespawnAt = now + trafficRespawnGap
  local ok, err = pcall(function()
    local ok2, group = pcall(variedTrafficGroup)
    if not ok2 then
      log("W", trafficTag, "varied pick failed, using stock group: " .. tostring(group))
      group = gameplay_traffic_trafficUtils.createTrafficGroup(1)
    end
    if not group or not group[1] then error("empty traffic group") end
    gameplay_traffic.spawnTraffic(1, group)
  end)
  if ok then
    trafficOwed = trafficOwed - 1
    trafficSpawnPending = now
    trafficLog("replacement requested")
  else
    trafficFailures = trafficFailures + 1
    log("W", trafficTag, "replacement spawn failed (" .. trafficFailures .. "): " .. tostring(err))
    if trafficFailures >= 5 then
      log("W", trafficTag, "giving up on " .. trafficOwed .. " owed traffic car(s)")
      trafficOwed = 0
      trafficFailures = 0
    end
  end
end

local function releaseStreetCar(vehicle)
  local id = vehicle:getID()
  local parked = parkedCars()[id]
  if parked then
    local parking = overhaul_integration_services_parking
    local pool = core_vehicleActivePooling.getPool("overhaulParking")
    if not pool or not pool:removeVeh(id) then return false end
    local spots = parking.getParkingSpots()
    local spot = spots and spots.objects and spots.objects[parked.parkingSpotId]
    if spot and spot.vehicle == id then spot.vehicle = nil end
    parking.removeVehicle(id)
    vehicle:setDynDataFieldbyName("ignoreTraffic", 0, "")
    vehicle:setDynDataFieldbyName("isParked", 0, "")
    vehicle.playerUsable = true
    gameplay_walk.removeVehicleFromBlacklist(id)
  else
    local wasTraffic = gameplay_traffic.getTrafficData()[id] ~= nil
    trafficLog("theft, before removing traffic car " .. id)
    stolenTraffic[id] = true
    gameplay_traffic.removeTraffic(id)
    if wasTraffic then trafficOwed = math.min(trafficMaxOwed, trafficOwed + 1) end
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

-- reward: the XP and theft counters this theft earns ({xp, label, clean, carjacked}). They are paid when the
-- car is stored, so a car that is ditched or seized before storage earns nothing.
local function begin(vehicle, source, seller, value, delay, organizationId, immediate, reward)
  liveId = vehicle:getID()
  state.serial = state.serial + 1
  -- Every case you are already holding makes the report come in sooner.
  delay = delay / (1 + 0.35 * #state.cases)
  local reportAt = gameTime() + math.max(1, math.ceil(delay))
  table.insert(state.cases, {serial = state.serial, source = source, seller = seller, value = tonumber(value) or 0,
    reportAt = reportAt, heatHotUntil = reportAt + heatHotSeconds,
    heatWarmUntil = reportAt + heatHotSeconds + heatWarmSeconds, phase = "transit", immediate = immediate or nil,
    reward = reward})
  patrolCheck = 0
  if source == "testDrive" then
    state.bans[seller] = gameTime() + 1800
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
  if immediate then
    notify("The driver saw you take the vehicle. Police are responding. Lose them and store it at a garage you own to earn the XP.")
  else
    notify("Vehicle taken. Drive to a garage you own and press " .. keyLabel() .. " to store it and earn the XP.")
  end
end

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
local lastStoreRefusal
local parkedTicks = 0 -- seconds the carried car has sat still inside an owned garage
local function store(vehicle, auto)
  local case = transitCase()
  if not case then return end
  local function refuse(message)
    if not auto or message ~= lastStoreRefusal then notify(message) end
    lastStoreRefusal = message
  end
  local pursuit = overhaul_integration_services_police.getPursuitData(liveId)
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
  local space = manager.isGarageSpace(garage.id)
  if not space or not space[1] or not inventory().hasFreeSlot() then
    refuse("This garage has no free vehicle slots.")
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
  local id = inventory().addVehicle(liveId, nil, {owned = true, takesNoInventorySpace = false})
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
  liveId = nil
  lastStoreRefusal = nil
  parkedTicks = 0
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
  if taken then vehicle = taken end
  if startMotor then
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

local function checkIgnition(vehicle, seller, testDrive, complete)
  ignitionToken = ignitionToken + 1
  ignition = {id = vehicle:getID(), token = ignitionToken, seller = seller, testDrive = testDrive,
    complete = complete, probeTime = 2}
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
  local cursor = (math.max(0, time) * ignitionSpeeds[challenge.stage]) % 30
  if cursor > 15 then cursor = 30 - cursor end
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
    remaining = challenge.remaining, duration = ignitionSeconds, inTarget = inTarget,
    started = challenge.started == true, feedback = challenge.feedback ~= nil,
    missed = challenge.feedbackKind == "miss", penalty = challenge.missPenalty or ignitionMissPenalty}
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
    return
  end
  if running then
    finishIgnition(challenge, vehicle, false)
    return
  end
  challenge.stage, challenge.time, challenge.remaining = 1, 0, ignitionSeconds
  -- Vehicle Theft perks, fixed for this attempt.
  challenge.widthScale = perk("ignitionWidth", 1)
  challenge.missPenalty = perk("missPenalty", ignitionMissPenalty)
  challenge.target = math.random(4, 12)
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
      challenge.target = math.random(4, 12)
      challenge.time, challenge.feedback, challenge.feedbackKind = 0, 0.5, "match"
      publishIgnition()
    end
  end
end

local function updateIgnition(dt)
  local challenge = ignition
  if not canContinueIgnition(challenge) then
    failIgnition(challenge, "The vehicle is no longer available for ignition bypass.")
    return
  end
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

function M.attempt()
  -- Global action bindings can fire while the phone UI has focus (notably mouse buttons).
  if appOpen then return end
  if not load() or not gameplay_traffic or not gameplay_walk or not overhaul_integration_services_police then return end
  bindRls()
  local player = walkingPlayer()
  if not player then return end
  if transitCase() then
    if liveId == player:getID() then store(player)
    else notify("You are still carrying a stolen car. Store it in a garage you own, or walk away from it, first.") end
    return
  end
  if #state.cases >= caseLimit() then
    notify(string.format("You are already handling %d stolen cars. Sell, strip or ditch one before taking another.", #state.cases))
    return
  end
  if attempted or ignition then return end
  if gameTime() < ignitionCooldown then
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
    notify("No eligible vehicle nearby. Walk up to a parked car, or step next to a civilian car driving slower than about 30 km/h.")
    return
  end
  if parkedCars()[nearest] then
    local wait = perk("parkedWait", 4)
    attempted = {id = nearest, remaining = wait}
    notify(string.format("Stay beside the vehicle for %d seconds.", wait))
  else
    -- A driver is present: flag the car down and pull them out.
    forceStop(getObjectByID(nearest))
    attempted = {id = nearest, remaining = 2.5}
    notify("You flag the car down. Stay next to it while the driver stops.")
  end
end

local function updateAttempt(dt)
  local player = walkingPlayer()
  local target = player and gameplay_walk.isWalking() and availableStreetCar(attempted.id, player)
  if not target then
    releaseForcedStop(attempted.id)
    attempted = nil
    notify("Vehicle theft attempt canceled.")
    return
  end
  attempted.remaining = attempted.remaining - dt
  if attempted.remaining > 0 then return end
  attempted = nil
  checkIgnition(target, nil, false, function(vehicle, result)
    local delay = streetReportDelay(vehicle, result)
    local fromTraffic = not parkedCars()[vehicle:getID()]
    if fromTraffic then
      -- The car is ours now: switch its AI off (this also releases the stop mode's parking brake).
      forcedStops[vehicle:getID()] = nil
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
    if not gameplay_traffic.getTrafficData()[id] then gameplay_traffic.insertTraffic(id, true, true) end
    local clean = not result.skipped and result.misses == 0
    begin(vehicle, "street", nil, 0, delay, nil, result.skipped, {
      xp = result.skipped and 12 or clean and 20 or 15, label = "Vehicle theft",
      clean = clean or nil, carjacked = (result.skipped and fromTraffic) or nil})
    return vehicle
  end)
end

local function currentValue(case)
  return math.max(0, tonumber(overhaul_career_market_valueCalculator.getInventoryVehicleSellValue(case.inventoryId)) or 0)
end

-- 23% of the car's value, at least $1,200; Vehicle Theft makes it cheaper.
local function identityFee(value)
  return math.max(1200, math.ceil(value * 0.23 * perk("identityFee", 1)))
end

local function startIdentity(case)
  if case.phase ~= "stored" or case.seizure or underSting(case) then return end
  local value = currentValue(case)
  local fee = identityFee(value)
  if not charge(fee, "Vehicle identity change", "service", false) then notify("Insufficient funds.") return end
  case.value = math.max(case.value, value)
  local seconds = perk("identityTime", 150)
  -- The fee is refunded if the car is driven out of the garage before the work is done.
  case.phase, case.readyAt, case.identityFee = "workshop", gameTime() + seconds, fee
  save()
  notify(string.format("Identity change started. Cost: %s. Ready in %d seconds.", money(fee), seconds))
end

-- Chop shop: a stored car can be stripped for parts instead of disguised. It takes less time and no
-- identity change or repaint, and nothing is handed to a buyer, so there is no raid. It pays less than an
-- average underground sale after the identity fee (about 31% of the value when cold), and a car with a
-- fresh report pays less again, so stripping it at once does not dodge the heat.
local chopSeconds = 90
local chopRates = {hot = 0.20, warm = 0.23, cold = 0.26}

local function chopValue(case)
  return math.floor(currentValue(case) * chopRates[heatStatus(case).stage] * perk("fenceValue", 1))
end

local function startChop(case)
  if case.phase ~= "stored" or case.seizure or underSting(case) then return end
  case.phase, case.readyAt = "chopping", gameTime() + chopSeconds
  save()
  notify(string.format("The car is being stripped for parts. The chop shop pays about %s in %d seconds.",
    money(chopValue(case)), chopSeconds))
end

local function finishChop(case)
  local price = chopValue(case)
  exitVehicle(inventory().getVehicleIdFromInventoryId(case.inventoryId))
  if inventory().removeVehicle(case.inventoryId) == false then return end
  openInvestigation(case)
  removeCase(case)
  overhaul_career_economy_payment.reward({money = {amount = price}},
    {label = "Chop shop parts sale", category = "sale", tags = {"vehicleTheft"}}, true)
  save()
  notify("The car was stripped and sold for parts. Payment received: " .. money(price))
  count("chopped")
  count("revenue", price)
  grantXp(10 + math.min(30, math.floor(price / 500)), "Parts sold to a chop shop")
end

-- Abandoning: walk away from a stolen car you have not stored. Beyond this distance, with no pursuit on
-- you, the car is left behind: no theft fine, but also no payout and no XP (that is paid on storage).
-- A test-drive car is the exception: the dealership knows who took it and still opens an investigation.
local abandonDistance = 120

local function checkAbandon(case)
  if case.phase ~= "transit" or not liveId or be:getPlayerVehicleID(0) == liveId then return false end
  local vehicle = getObjectByID(liveId)
  local player = walkingPlayer()
  if not vehicle or not player or distance(vehicle, player) < abandonDistance then return false end
  local pursuit = overhaul_integration_services_police.getPursuitData(liveId)
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

-- Underground market ------------------------------------------------------------------------------
-- After the identity change the vehicle is sold from the "Underground" phone app: list it at an asking
-- price, buyers send timed offers, and an offer can be taken as is or negotiated. The flow mirrors the
-- RLS marketplace (career/market/marketplace.lua and marketplace/negotiationPolicy.lua): a higher asking
-- price slows offers down, buyers have a patience budget, and counters close part of the gap each turn.

local undergroundAppId = "rls-underground"
local undergroundEvent = "RlsTheftUnderground"
local offerChannel = "rlsUnderground.newOffer"
local maxOffers = 4
local offerIntervalBase = 45 -- seconds between offers at a fair asking price
local offerTtlRange = {150, 300}

local buyerArchetypes = {
  chopShop = {label = "Chop shop", price = 0.84, patience = 0.7,
    quotes = {"I only want the parts. Cash, no questions.", "Parts are parts. Here's my number.",
      "It'll be in pieces by tonight. That's what it's worth to me."},
    hotQuote = "This one's still hot. I'm pricing in the attention, not just the parts.",
    warmQuote = "It's cooling off. Leave it quiet a little longer and you'll get a better number."},
  exporter = {label = "Exporter", price = 0.97, patience = 1.15,
    quotes = {"Container leaves Thursday. I can make room for it.", "Overseas buyers like this model. Fair price.",
      "Clean paperwork? Then we can talk."},
    hotQuote = "I can't put a hot car in a container. The low number covers the risk.",
    warmQuote = "The heat's dropping. I can do better once the report goes cold."},
  racer = {label = "Street racer", price = 0.92, patience = 0.85,
    quotes = {"Does it pull? I'll take it if it pulls.", "Need something nobody knows for Friday night.",
      "Cash now if you don't ask what it's for."},
    hotQuote = "Too many eyes on this one. Take the offer or wait it out.",
    warmQuote = "It's less risky now. Still, I know the paint in that report."},
  fixer = {label = "Fixer", price = 0.9, patience = 1.0,
    quotes = {"I have a client. I take my cut, you take yours.", "Quiet deal, quiet money.",
      "My people don't haggle long. Neither should you."},
    hotQuote = "Your car's still on the wire. My offer reflects the risk.",
    warmQuote = "The attention is fading. Give it more time and the price will improve."},
}
local buyerArchetypeKeys = {"chopShop", "exporter", "racer", "fixer"}
local buyerNames = {"Sly", "Dutch", "Moth", "Kestrel", "Rook", "Nico", "Viper", "Ghost", "Tank", "Mickey",
  "Juno", "Rafa", "Lazlo", "Pike", "Vera", "Bones", "Ox", "Silk", "Marek", "Duke"}

local function roundPrice(value)
  return math.max(50, math.floor((tonumber(value) or 0) / 50 + 0.5) * 50)
end

-- What the underground pays; fresh reports draw the deepest discount.
local function undergroundValue(case, now)
  local heat = heatStatus(case, now)
  return math.floor(currentValue(case) * heat.multiplier * perk("fenceValue", 1)), heat
end

-- marketplace.lua offerTimeMultiplierForRatio: cheap listings get offers sooner, greedy ones later.
local function offerTimeMultiplier(ratio)
  if ratio < 0.98 then
    local t = math.max(0, math.min(1, (0.98 - ratio) / (0.98 - 0.85)))
    return 1 + (0.4 - 1) * t
  elseif ratio > 1.1 then
    local t = math.max(0, math.min(1, (ratio - 1.1) / (1.5 - 1.1)))
    return 1 + (4 - 1) * t
  end
  return 1
end

local function scheduleNextOffer(listing, base, now)
  local multiplier = offerTimeMultiplier(listing.price / math.max(base, 1))
  local interval = offerIntervalBase * multiplier * perk("offerPace", 1)
  listing.nextOfferAt = now + math.floor(interval + (math.random() * 1.2 - 0.6) * interval)
end

local function newOfferId(listing)
  local id
  repeat
    id = math.random(100000, 999999)
    local taken = false
    for _, offer in ipairs(listing.offers) do if offer.id == id then taken = true end end
  until not taken
  return id
end

local function notifyPhone(title, message)
  if not overhaul_phone_apps_layout then pcall(extensions.load, "overhaul_phone_apps_layout") end
  local layout = overhaul_phone_apps_layout
  if not (layout and layout.fireNotification) then return end
  pcall(layout.fireNotification, offerChannel,
    {title = title, message = message, kind = "invite", ttl = 8, source = "Underground"}, {appId = undergroundAppId})
end

-- marketplace.lua generateOffer, scaled to underground prices and buyer types.
local function generateOffer(case, now)
  local listing = case.listing
  local base, heat = undergroundValue(case, now)
  if base <= 0 then return end
  local key = buyerArchetypeKeys[math.random(1, #buyerArchetypeKeys)]
  local archetype = buyerArchetypes[key]
  local noise = 0.9 + math.random() * 0.15
  local value = base * archetype.price * noise
  local ratio = listing.price / math.max(base, 1)
  if ratio < 0.9 then
    value = math.min(value, listing.price * (1.05 + math.random() * 0.1))
  elseif ratio > 1.1 then
    value = math.min(value, base * (0.95 + math.random() * 0.1))
  end
  -- An undercover cop poses as an ordinary buyer of any type. The only tell is the money: the police want
  -- the deal to happen, so the offer is a little too good, and they are patient in a negotiation.
  local undercover = math.random() < (undercoverChances[heat.stage] or 0)
  if undercover then value = value * (1.05 + math.random() * 0.05) end
  local offer = {
    id = newOfferId(listing),
    buyer = buyerNames[math.random(1, #buyerNames)],
    archetype = key,
    value = roundPrice(value),
    createdAt = now,
    expiresAt = now + math.random(offerTtlRange[1], offerTtlRange[2]),
    quote = heat.stage == "hot" and archetype.hotQuote
      or heat.stage == "warm" and archetype.warmQuote
      or archetype.quotes[math.random(1, #archetype.quotes)],
    undercover = undercover or nil, -- never sent to the app (getUndergroundState copies named fields only)
  }
  table.insert(listing.offers, offer)
  notifyPhone("New underground offer", string.format("%s offers %s for your vehicle.", offer.buyer, money(offer.value)))
  return offer
end

local function findOffer(case, offerId)
  local listing = case and case.listing
  if not listing then return end
  for index, offer in ipairs(listing.offers) do
    if offer.id == offerId then return offer, index end
  end
end

local function removeOffer(case, offerId)
  local _, index = findOffer(case, offerId)
  if index then table.remove(case.listing.offers, index) end
end

-- Buyers only meet a parked car: never one the player is driving, and never one the police are chasing
-- (handing it over would make it vanish mid-pursuit). Returns the reason, or nil when the handover can happen.
local function handoverBlocked(case)
  local vehId = case and caseVehicleId(case)
  if not vehId then return end
  if be:getPlayerVehicleID(0) == vehId then return "Park the car and get out before the handover." end
  local police = overhaul_integration_services_police
  local pursuit = police and police.getPursuitData(vehId)
  if pursuit and (pursuit.mode or 0) ~= 0 then return "No buyer will meet a car the police are chasing." end
end

-- Undercover buyers ---------------------------------------------------------------------------------
-- Accepting an undercover cop's offer is a sting, not a sale. The listing is gone and the car stays yours,
-- but the police now know its new plate and the colour the buyer saw, so it is back to an undisguised,
-- freshly reported car: it needs another identity change and another repaint. state.sting then hunts the
-- seller: the next vehicle the player drives (at once if they are driving) gets an immediate pursuit, like a
-- carjacking report. Lose it and the operation ends; get arrested and the car is seized with the theft fine.

-- Starts the sting pursuit on the vehicle the player is driving. Returns true once a chase is on.
local function startStingPursuit()
  local sting = state.sting
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
  state.sting = {serial = case.serial, untilAt = now + stingSeconds}
  lastResult = {kind = "sting"}
  save()
  notify("The buyer was an undercover cop. The deal is off and the car's new plate is burned.")
  if not startStingPursuit() then
    notify("Undercover units are looking for you. The next time you drive, expect a chase.")
  end
  return "sting"
end

-- Hands the car over at the agreed price. Returns "sold", "raided", "sting" or nil when it cannot happen now.
-- undercover: the buyer was an undercover cop, so the handover springs the sting instead.
local function completeUndergroundSale(case, price, negotiated, undercover)
  price = math.floor(tonumber(price) or 0)
  if price <= 0 or not vehicleCase(case.inventoryId) or case.seizure then return end
  local blocked = handoverBlocked(case)
  if blocked then
    notify(blocked)
    return
  end
  if undercover then return springSting(case) end
  if repainted(case) == false and math.random() < paintStingChance() then
    seize("The buyer's contact matched the paint to the theft report and police raided the handover.", case)
    lastResult = {kind = "raided"}
    return "raided"
  end
  exitVehicle(inventory().getVehicleIdFromInventoryId(case.inventoryId))
  if inventory().removeVehicle(case.inventoryId) == false then
    notify("The vehicle cannot be handed over right now.")
    return
  end
  openInvestigation(case)
  removeCase(case)
  overhaul_career_economy_payment.reward({money = {amount = price}},
    {label = "Underground vehicle sale", category = "sale", tags = {"vehicleTheft"}}, true)
  save()
  notify("Vehicle handed over. Payment received: " .. money(price))
  count("sold")
  count("revenue", price)
  grantXp(15 + math.min(45, math.floor(price / 400)) + (negotiated and 5 or 0), "Underground vehicle sale")
  lastResult = {kind = "sold", price = price}
  return "sold"
end

-- The case the Underground app is showing: the one the player picked, else the first stored car,
-- else the car still being carried.
local function selectedCase()
  local list = state and state.cases or {}
  local first
  for _, case in ipairs(list) do
    if case.serial == selectedSerial then return case end
    if not first and case.phase ~= "transit" then first = case end
  end
  return first or list[1]
end

local function sellableCase()
  local case = selectedCase()
  if case and case.phase == "listed" and case.listing and vehicleCase(case.inventoryId) and not case.seizure then
    return case
  end
end

local function negotiationView()
  local n = negotiation
  if not n then return nil end
  return {
    offerId = n.offerId, opponentName = n.opponentName, quote = n.quote, patience = n.patience,
    history = n.history, status = n.status, theirOffer = n.theirOffer, myOffer = n.myOffer,
    startingPrice = n.startingPrice, marketValue = n.marketValue, result = n.result,
  }
end

function M.getUndergroundState()
  if not load() then return {available = false} end
  local view = {available = true, result = lastResult, negotiation = negotiationView(), offers = {}}
  view.skill = skillProgress()
  view.limit = caseLimit()
  -- The rates and risks the app explains, with the player's perks and open cases applied.
  local fence = perk("fenceValue", 1)
  view.rates = {}
  for stage, multiplier in pairs(heatMultipliers) do view.rates[stage] = math.floor(multiplier * fence * 100 + 0.5) end
  view.raidChance = math.floor(paintStingChance() * 100 + 0.5)
  view.cases = {}
  local now = gameTime()
  if state.sting then
    view.sting = {serial = state.sting.serial, chasing = state.sting.pursuing ~= nil,
      remaining = math.max(0, state.sting.untilAt - now)}
  end
  local case = selectedCase()
  for _, other in ipairs(state.cases) do
    local record = other.inventoryId and inventory().getVehicles()[other.inventoryId]
    local heat = heatStatus(other, now)
    table.insert(view.cases, {serial = other.serial, phase = other.phase,
      name = record and record.niceName or "Stolen vehicle", selected = other == case, heatLabel = heat.label})
  end
  if not case then return view end
  local record = case.inventoryId and inventory().getVehicles()[case.inventoryId]
  local vehicle = {serial = case.serial, phase = case.phase, identity = case.identity, source = case.source,
    repainted = repainted(case)}
  if record then
    vehicle.name = record.niceName
    vehicle.thumbnail = inventory().getVehicleThumbnail and inventory().getVehicleThumbnail(case.inventoryId)
  end
  if case.phase == "chopping" then vehicle.workshopRemaining = math.max(0, (case.readyAt or now) - now) end
  if case.phase == "workshop" then vehicle.workshopRemaining = math.max(0, (case.readyAt or now) - now) end
  if case.inventoryId and record then
    local base, heat = undergroundValue(case, now)
    vehicle.marketValue, vehicle.heat, vehicle.suggestedPrice = base, heat, roundPrice(base)
    vehicle.hot = heat.stage == "hot"
    vehicle.handoverBlocked = handoverBlocked(case)
  end
  if case.listing then
    vehicle.listedPrice = case.listing.price
    vehicle.nextOfferIn = case.listing.nextOfferAt and math.max(0, case.listing.nextOfferAt - now) or nil
    for _, offer in ipairs(case.listing.offers) do
      local archetype = buyerArchetypes[offer.archetype] or {}
      table.insert(view.offers, {id = offer.id, buyer = offer.buyer, archetype = archetype.label, value = offer.value,
        quote = offer.quote, expiresIn = math.max(0, offer.expiresAt - now)})
    end
    table.sort(view.offers, function(a, b) return a.value > b.value end)
  end
  view.vehicle = vehicle
  return view
end

local function publishUnderground()
  guihooks.trigger(undergroundEvent, M.getUndergroundState())
end

function M.undergroundSetOpen(open)
  appOpen = open == true
  if appOpen then publishUnderground() end
end

function M.undergroundSelect(serial)
  if not load() or negotiation then return end
  if findCase(tonumber(serial)) then selectedSerial = tonumber(serial) end
  publishUnderground()
end

function M.undergroundList(price)
  if not load() then return end
  local case = selectedCase()
  if not case or case.phase ~= "ready" or not vehicleCase(case.inventoryId) or case.seizure then return end
  price = roundPrice(price)
  local now = gameTime()
  case.phase = "listed"
  case.listing = {price = price, listedAt = now, offers = {}, nextOfferAt = now + math.random(10, 25)}
  lastResult = nil
  save()
  publishUnderground()
end

function M.undergroundUnlist()
  if not load() then return end
  local case = sellableCase()
  if not case then return end
  case.phase, case.listing, negotiation = "ready", nil, nil
  save()
  publishUnderground()
end

function M.undergroundSetPrice(price)
  if not load() then return end
  local case = sellableCase()
  if not case then return end
  case.listing.price = roundPrice(price)
  scheduleNextOffer(case.listing, undergroundValue(case), gameTime())
  save()
  publishUnderground()
end

function M.undergroundAccept(offerId)
  if not load() then return end
  local case = sellableCase()
  local offer = findOffer(case, tonumber(offerId))
  if not offer or offer.expiresAt <= gameTime() then return end
  negotiation = nil
  completeUndergroundSale(case, offer.value, false, offer.undercover)
  publishUnderground()
end

function M.undergroundDecline(offerId)
  if not load() then return end
  local case = sellableCase()
  if not case then return end
  removeOffer(case, tonumber(offerId))
  save()
  publishUnderground()
end

function M.undergroundDismissResult()
  lastResult = nil
  if negotiation and negotiation.result then negotiation = nil end
  publishUnderground()
end

-- Negotiation (selling side of marketplace/negotiation.lua + negotiationPolicy.lua) ----------------

-- negotiationPolicy.sellingPatienceDrop for a private buyer: the further the ask is from the
-- underground value, the faster patience runs out; the archetype scales it.
local function sellingPatienceDrop(myOffer, base, archetype)
  local scale = math.max(base, 500)
  local gap = math.abs(myOffer - base)
  local gapPercent = gap / scale * 100
  local priceScale = math.min(1, scale / 1000)
  local drop = gapPercent * 3 * priceScale + (gap / 100) * 8 * (1 - priceScale) + math.random() * 12
  return drop / 100 / (archetype.patience or 1)
end

-- negotiationPolicy.privateCounterOffer, selling side: close 30-70% of the gap, never above the budget.
local function buyerCounter(myOffer, theirOffer, maxBuyerPrice)
  local movement = math.abs(myOffer - theirOffer) * (0.3 + math.random() * 0.4)
  local counter = math.max(theirOffer, roundPrice(theirOffer + movement))
  return math.min(counter, maxBuyerPrice)
end

function M.undergroundNegotiate(offerId)
  if not load() then return end
  local case = sellableCase()
  local offer = findOffer(case, tonumber(offerId))
  if not offer or offer.expiresAt <= gameTime() then return end
  local base = undergroundValue(case)
  local archetype = buyerArchetypes[offer.archetype] or buyerArchetypes.fixer
  local asking = math.max(case.listing.price, offer.value)
  negotiation = {
    serial = case.serial, offerId = offer.id, opponentName = offer.buyer .. " (" .. (archetype.label or "Buyer") .. ")",
    quote = offer.quote, archetype = archetype, patience = 1, token = (negotiation and negotiation.token or 0) + 1,
    theirOffer = offer.value, myOffer = asking, startingPrice = asking, marketValue = base,
    maxBuyerPrice = math.max(base * 1.12, offer.value * 1.2), status = "initial", undercover = offer.undercover,
    history = {{myOffer = asking, negotiationStatus = "initial"}, {theirOffer = offer.value, negotiationStatus = "initial"}},
  }
  publishUnderground()
end

local function settleNegotiationSale(n, price)
  local case = findCase(n.serial)
  local opening = n.history[2] and n.history[2].theirOffer or price
  local outcome = case and completeUndergroundSale(case, price, price > opening, n.undercover)
  n.result = outcome and {kind = outcome, price = price} or {kind = "failed"}
end

function M.undergroundCounter(price)
  local n = negotiation
  price = math.floor(tonumber(price) or 0)
  if not n or n.result or n.status == "thinking" or n.status == "typing" then return end
  if not (price > n.theirOffer and price <= n.myOffer) then return end
  n.myOffer, n.status = price, "thinking"
  table.insert(n.history, {myOffer = price})
  publishUnderground()
  local token = n.token
  core_jobsystem.create(function(job)
    local thinking = 1 + math.random() * 1.2
    job.sleep(thinking)
    if negotiation ~= n or n.token ~= token then return end
    n.status = "typing"
    publishUnderground()
    job.sleep(thinking)
    if negotiation ~= n or n.token ~= token then return end
    -- An undercover cop wants the deal to close, so they lose patience at half the usual rate.
    local drop = sellingPatienceDrop(n.myOffer, n.marketValue, n.archetype) * (n.undercover and 0.5 or 1)
    n.patience = math.max(0, n.patience - drop)
    if n.patience <= 0 then
      n.status = "failed"
      local case = findCase(n.serial)
      if case then removeOffer(case, n.offerId); save() end
    else
      local counter = buyerCounter(n.myOffer, n.theirOffer, n.maxBuyerPrice)
      local blocked = counter >= n.myOffer and handoverBlocked(findCase(n.serial))
      if blocked then
        -- The buyer agrees to the price but will not meet yet: the deal stands until the player takes it.
        n.theirOffer, n.status = math.min(n.myOffer, n.maxBuyerPrice), "counterOffer"
        notify("The buyer agrees to " .. money(n.theirOffer) .. ". " .. blocked)
      elseif counter >= n.myOffer then
        n.theirOffer, n.status = math.min(n.myOffer, n.maxBuyerPrice), "accepted"
      else
        n.theirOffer = counter
        n.status = n.patience <= 0.35 and "counterOfferLastChance" or "counterOffer"
      end
    end
    table.insert(n.history, {theirOffer = n.theirOffer, negotiationStatus = n.status})
    if n.status == "accepted" then settleNegotiationSale(n, n.theirOffer) end
    publishUnderground()
  end, 1)
end

function M.undergroundTakeOffer()
  local n = negotiation
  if not n or n.result or n.status == "failed" or n.status == "thinking" or n.status == "typing" then return end
  local blocked = handoverBlocked(findCase(n.serial))
  if blocked then
    notify(blocked)
    return
  end
  n.status = "accepted"
  table.insert(n.history, {myOffer = n.theirOffer, negotiationStatus = "accepted"})
  settleNegotiationSale(n, n.theirOffer)
  publishUnderground()
end

function M.undergroundCancelNegotiation()
  if not negotiation then return end
  negotiation = nil
  publishUnderground()
end

-- Called every second from onUpdate: expire offers and bring in new ones.
local function updateListing(case, now)
  local listing = case.listing
  local changed = false
  for index = #listing.offers, 1, -1 do
    local offer = listing.offers[index]
    if offer.expiresAt <= now and not (negotiation and negotiation.offerId == offer.id) then
      table.remove(listing.offers, index)
      changed = true
    end
  end
  if not listing.nextOfferAt then scheduleNextOffer(listing, undergroundValue(case), now) end
  if now >= listing.nextOfferAt then
    if #listing.offers < maxOffers and generateOffer(case, now) then changed = true end
    scheduleNextOffer(listing, undergroundValue(case), now)
  end
  if changed then save() end
end

local function addComputerRow(case, buttons)
  if not case.inventoryId or not vehicleCase(case.inventoryId) or case.seizure then return end
  local row = buttons.vehicleSpecific[case.inventoryId]
  if not row then return end
  -- RLS calls callback() unconditionally if a click gets through, so even a disabled row needs one.
  local function info(label)
    row.rlsTheft = {id = "rlsTheft", label = label, order = 80, disabled = true, callback = function() end}
  end
  if underSting(case) then
    info("Police are after this car: no crew will touch it until you lose them")
  elseif case.phase == "stored" then
    row.rlsTheft = {id = "rlsTheft", order = 80,
      label = "Change vehicle identity (" .. money(identityFee(currentValue(case))) .. ")",
      callback = function()
        if state and findCase(case.serial) == case and vehicleCase(case.inventoryId) then
          startIdentity(case)
          overhaul_career_career.closeAllMenus()
        end
      end}
    row.rlsTheftChop = {id = "rlsTheftChop", order = 81,
      label = string.format("Strip for parts (~%s, %d s)", money(chopValue(case)), chopSeconds),
      callback = function()
        if state and findCase(case.serial) == case and vehicleCase(case.inventoryId) then
          startChop(case)
          overhaul_career_career.closeAllMenus()
        end
      end}
  elseif case.phase == "chopping" then
    info("Being stripped for parts")
  elseif case.phase == "workshop" then
    info("Identity change in progress")
  elseif case.phase == "ready" then
    info("Ready to sell: list it in the Underground phone app")
  elseif case.phase == "listed" then
    info("Listed in the Underground phone app")
  end
end

function M.onOverhaulComputerAddFunctions(menu, buttons)
  if not load() then return end
  for _, case in ipairs(state.cases) do addComputerRow(case, buttons) end
end

-- True while the player drives the case's car outside an owned garage. Only getting in does not count.
local function drivenOutOfGarage(case)
  local vehId = caseVehicleId(case)
  if not vehId or be:getPlayerVehicleID(0) ~= vehId then return false end
  local vehicle = getObjectByID(vehId)
  local garage = vehicle and ownedGarageNear(vehicle)
  return vehicle ~= nil and not (garage and insideGarage(vehicle, garage))
end

local function updateCase(case, now)
  if case.seizure then
    if not case.inventoryId or not vehicleCase(case.inventoryId)
      or overhaul_career_logistics_general.canRemoveLogisticsVehicle(case.inventoryId) then
      seize(case.seizure, case)
    end
    return
  end
  if case.inventoryId and not vehicleCase(case.inventoryId) then
    -- The inventory record went away outside the mod's guarded sale paths: the car is gone, the theft stands.
    local amount = fineFor(case)
    charge(amount, "Missing stolen vehicle", "fine", true)
    removeCase(case)
    save()
    notify("A stolen vehicle left your garage outside the underground. The theft is on record. Fine: " .. money(amount))
    return
  end
  if case.phase == "transit" and not liveId then
    removeCase(case)
    charge(fineFor(case), "Unresolved vehicle theft", "fine", true)
    save()
    notify("The unstored vehicle was recovered and a theft fine was charged.")
    return
  end
  if case.phase == "chopping" then
    -- Driving the car out of the garage interrupts the crew: no payment, the car is yours again.
    if drivenOutOfGarage(case) then
      case.phase, case.readyAt = "stored", nil
      save()
      notify("You drove the car out before the crew finished. Nothing was paid.")
    elseif now >= case.readyAt then
      finishChop(case)
    end
    return
  end
  if checkAbandon(case) then return end
  if case.phase == "workshop" and drivenOutOfGarage(case) then
    -- Same rule as the chop shop: the work stops when the car leaves. The workshop returns the fee.
    local refund = tonumber(case.identityFee) or 0
    case.phase, case.readyAt, case.identityFee = "stored", nil, nil
    if refund > 0 then
      overhaul_career_economy_payment.reward({money = {amount = refund}},
        {label = "Vehicle identity change refund", category = "service", tags = {"vehicleTheft"}}, true)
    end
    save()
    notify("You drove the car out before the new identity was finished. The workshop refunded " .. money(refund) .. ".")
    return
  elseif case.phase == "workshop" and now >= case.readyAt then
    case.identityFee = nil
    local id = case.inventoryId
    -- A plate burned in an undercover sting is known to the police: each new identity uses the next series.
    local series = {"GX", "GY", "GZ", "GW"}
    case.identity = string.format("%s%06d", series[(case.identityRevision or 0) % #series + 1], case.serial % 1000000)
    local record = inventory().getVehicles()[id]
    if record.config then record.config.licenseName = case.identity end
    local vehicleId = inventory().getVehicleIdFromInventoryId(id)
    if vehicleId and getObjectByID(vehicleId) then core_vehicles.setPlateText(case.identity, vehicleId) end
    inventory().setVehicleDirty(id)
    case.phase = "ready"
    grantXp(5, "Vehicle identity changed")
    if repainted(case) == false then
      notify("Identity change complete. The paint still matches the theft report: repaint it at the garage computer before selling it in the Underground phone app.")
    else
      notify("Identity change complete. Sell it from the Underground phone app.")
    end
    save()
  elseif case.phase == "listed" and case.listing then
    updateListing(case, now)
  end

  -- Storing used to depend on a key press the player only heard about once. Remind them near an owned
  -- garage, and store automatically when they park inside it and get out.
  -- parkedTicks belongs to the transit case alone: other open cases must not reset it.
  if case.phase == "transit" then
    local stolen = liveId and getObjectByID(liveId)
    if stolen and ownedGarageNear(stolen) then
      if be:getPlayerVehicleID(0) == liveId then
        -- A car that is only parked, never stored, is not in the inventory: saving and reloading would lose it.
        -- Once it sits still inside the garage, store it without waiting for a key press or for the player to get out.
        if stolen:getVelocity():length() <= 1 then
          parkedTicks = parkedTicks + 1
          if parkedTicks >= 3 and store(stolen, true) then return end
        else
          parkedTicks = 0
        end
        ui_message("Stolen vehicle: stop inside the garage and it will be stored (or press " .. keyLabel() .. ").",
          2, "rlsVehicleTheftStore")
      elseif gameplay_walk.isWalking() and store(stolen, true) then
        return
      end
    else
      parkedTicks = 0
    end
  end

  -- After the identity change only an unrepainted car can still be matched to the theft report.
  if disguised(case) then return end
  local id = case.inventoryId and inventory().getVehicleIdFromInventoryId(case.inventoryId) or liveId
  local vehicle = id and getObjectByID(id)
  if not vehicle then
    if case.phase == "transit" then liveId = nil end
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
  if case.immediate then
    -- Carjacking: the driver calls it in, so the nearest unit responds without having seen the car.
    -- One-shot: once evaded, the case falls back to the sighting rule below.
    case.immediate = nil
    local responderId = police.getNearestPoliceVehicle(id, false, true)
    police.setPursuitMode(1, id, responderId and {responderId} or nil)
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
      police.setPursuitMode(1, id, {patrolId})
    elseif case.sightedPatrol ~= patrolId then
      -- New plate, reported paint: each patrol gets one look at the car.
      case.sightedPatrol = patrolId
      if math.random() < paintRecognitionChance() * (stage == "cold" and 0.5 or 1) then
        case.heatHotUntil, case.heatWarmUntil = now + heatHotSeconds, now + heatHotSeconds + heatWarmSeconds
        case.recognizedAt = now
        notify("A patrol recognized the stolen vehicle by its original paint. It's hot again; repaint it to break the link.")
        police.setPursuitMode(1, id, {patrolId})
      end
      save()
    end
  end
end

-- Runs the undercover operation every second: chase the next vehicle the player drives, and end the
-- operation when the stung car is gone, when a chase fades out without an evade or arrest event, or when
-- nobody was chased before its time ran out.
local function updateSting(now)
  local sting = state.sting
  if not sting then return end
  local function finish(message)
    state.sting = nil
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

function M.onUpdate(dtReal, dt)
  if not load() then
    ignition = nil
    return
  end
  state.clock = state.clock + (tonumber(dtReal) or 0)
  if ignition then updateIgnition(dtReal) end
  updateStarter(dtReal)
  if attempted then updateAttempt(dt) end
  -- The app's countdowns (identity change, next offer, offer expiry) run on the play-time clock, which
  -- follows real time, so refresh the open app on real time too: a paused simulation must not freeze them.
  appTick = appTick - dtReal
  if appOpen and appTick <= 0 then
    appTick = 1
    publishUnderground()
  end
  patrolCheck = patrolCheck - dt
  if patrolCheck > 0 then return end
  patrolCheck = 1
  bindRls()
  local now = gameTime()
  for i = #state.citations, 1, -1 do
    local citation = state.citations[i]
    if now >= citation.due then
      table.remove(state.citations, i)
      charge(citation.amount, "Dealership test-drive investigation", "fine", true)
      notify("Test-drive investigation closed. Fine: " .. money(citation.amount))
      save()
    end
  end
  for index = #state.cases, 1, -1 do
    if state.cases[index] then updateCase(state.cases[index], now) end
  end
  updateSting(now)
  updateTrafficTopUp(now)
end

-- Traffic hooks, used for the top-up and for the log: every car that leaves or joins traffic is recorded,
-- so a drop that is not a theft shows up as "removed (other)".
function M.onTrafficVehicleRemoved(id)
  if not state then return end
  local theft = stolenTraffic[id]
  stolenTraffic[id] = nil
  trafficLog("traffic car " .. tostring(id) .. " removed (" .. (theft and "theft" or "other") .. ")")
end

function M.onTrafficVehicleAdded(id)
  if not state then return end
  if trafficSpawnPending then
    trafficSpawnPending = nil
    trafficLog("replacement car " .. tostring(id) .. " joined traffic")
  end
end

-- Traffic was switched off: nothing is owed any more.
function M.onTrafficStopped()
  if trafficOwed > 0 then trafficLog("traffic stopped, dropping owed cars") end
  resetTrafficTopUp()
end

function M.onPursuitAction(id, action)
  if not state then return end
  -- The undercover chase is on whatever the player was driving, usually not the stolen car itself.
  local sting = state.sting
  if sting and sting.pursuing == id and (action == "evade" or action == "arrest") then
    state.sting = nil
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
        local case = state and findCase(serial)
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
      if state and findCase(arrestedCase.serial) == arrestedCase and not disguised(arrestedCase)
        and caseVehicleId(arrestedCase) == id then
        seize("Police identified the stolen vehicle.", arrestedCase)
      end
    end, 1)
  end
end

function M.onOverhaulSaveCurrentProfile(path)
  if state then overhaul_career_saveSystem.jsonWriteFileSafe(path .. saveFile, state, true) end
end

function M.onOverhaulBeforeSetProfile()
  profile, state, attempted, liveId = nil, nil, nil, nil
  negotiation, lastResult = nil, nil
  ignition, ignitionCooldown, starter = nil, 0, nil
  forcedStops, bypassMisses, parkedTicks = {}, {}, 0
  resetTrafficTopUp()
end

function M.onClientEndMission()
  attempted, liveId, ignition, starter = nil, nil, nil, nil
  forcedStops, bypassMisses, parkedTicks = {}, {}, 0
  resetTrafficTopUp()
  -- Vehicle ids do not survive a level change: an ongoing undercover chase starts over on the next drive.
  if state and state.sting then state.sting.pursuing = nil end
end

function M.onExtensionUnloaded()
  for key, entry in pairs(bindings) do
    if entry.owner[key] == entry.wrapper then entry.owner[key] = entry.original end
  end
end

return M
