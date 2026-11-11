local M = {}
local saveFile = "/career/rlsVehicleTheft.json"
local state, profile, attempted, liveId, patrolCheck
local bindings = {}
local ignition, ignitionToken, ignitionCooldown = nil, 0, 0
-- Underground app session state (not saved): the open negotiation, whether the app is showing, last sale.
local negotiation, appOpen, lastResult
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
local starter
local rules = {
  street = {fine = 0.34, minimum = 3000},
  inspection = {fine = 0.42, minimum = 4500, reputation = 120},
  testDrive = {fine = 0.50, minimum = 5500, reputation = 220},
}

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
    -- Before 0.6 a single offer was requested at the garage computer; those cases go back to "ready"
    -- so the vehicle can be listed in the Underground phone app.
    if state.case and state.case.phase == "offer" then
      state.case.phase, state.case.offer, state.case.expiresAt = "ready", nil, nil
    end
    attempted, liveId, patrolCheck = nil, nil, 0
    negotiation, lastResult = nil, nil
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

local function vehicleCase(id)
  local case = state and state.case
  if not case or case.inventoryId ~= tonumber(id) then return end
  local record = inventory().getVehicles()[case.inventoryId]
  if record and record.rlsTheftCase == case.serial then return case end
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
local function paintRecognitionChance() return perk("paintRecognition", 0.3) end
local function paintStingChance() return perk("paintSting", 0.2) end

local function seize(reason)
  local case = state.case
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
  elseif liveId then
    local vehicle = getObjectByID(liveId)
    if vehicle then
      exitVehicle(liveId)
      vehicle:delete()
    end
  end
  local amount = fineFor(case)
  charge(amount, reason, "fine", true)
  state.case, liveId = nil, nil
  save()
  notify(reason .. " Vehicle seized. Fine: " .. money(amount))
  return false
end

local function rejectTransfer(id)
  if not load() or not vehicleCase(id) then return nil end
  local reason = state.case.identity and "Registration check failed during title transfer."
    or "The title transfer flagged the vehicle as stolen."
  seize(reason)
  return false
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
  bind(overhaul_career_progression_skillsPage, "getLandingPageData", decorateSkillsPage)
  bind(overhaul_career_market_testDrive, "start", function(original)
    return function(...)
      local _, seller = inspectedDealer()
      if seller and load() and (state.bans[seller] or 0) > os.time() then
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
    gameplay_traffic.removeTraffic(id)
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

local function begin(vehicle, source, seller, value, delay, organizationId, immediate)
  liveId = vehicle:getID()
  state.serial = state.serial + 1
  state.case = {serial = state.serial, source = source, seller = seller, value = tonumber(value) or 0,
    reportAt = os.time() + math.max(1, math.ceil(delay)), phase = "transit", immediate = immediate or nil}
  patrolCheck = 0
  if source == "testDrive" then
    state.bans[seller] = os.time() + 1800
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
    notify("The driver saw you take the vehicle. Police are responding. Lose them and store it at a garage you own.")
  else
    notify("Vehicle taken. Drive to a garage you own and press Ctrl+Shift+J to store it.")
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
local function store(vehicle, auto)
  local case = state.case
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
  if not inventory().moveVehicleToGarage(id, garage.id) then
    seize("Garage intake failed.")
    return
  end
  inventory().setVehicleDirty(id)
  case.value = math.max(case.value, tonumber(overhaul_career_market_valueCalculator.getInventoryVehicleSellValue(id)) or 0)
  -- From here the case follows the inventory id; a stale object id could match an unrelated vehicle later.
  liveId = nil
  lastStoreRefusal = nil
  save()
  notify("Vehicle stored. At the garage computer, change its identity and repaint it; the original paint is in the theft report.")
  grantXp(10, "Stolen vehicle stored")
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
  ignitionCooldown = os.time() + ignitionFailCooldown
  notify(message)
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
  if extensions.ui_router.navigate(ignitionRoute) == false then
    ignition = nil
    notify("Could not open the ignition bypass screen.")
  end
end

function M.ignitionInput(token, action)
  local challenge = ignition
  if not challenge or challenge.token ~= token or not challenge.stage then return end
  if action == "leave" then
    ignition = nil
    return
  end
  if action == "cancel" then
    closeIgnition(challenge)
    releaseForcedStop(challenge.id)
    notify("Ignition bypass canceled.")
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
    if challenge.idle > 45 then
      closeIgnition(challenge)
      releaseForcedStop(challenge.id)
    end
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
  if not load() or not gameplay_traffic or not gameplay_walk or not overhaul_integration_services_police then return end
  bindRls()
  local player = walkingPlayer()
  if not player then return end
  if state.case then
    if state.case.phase == "transit" and liveId == player:getID() then store(player)
    else notify("You already have an open vehicle theft case.") end
    return
  end
  if attempted or ignition then return end
  if os.time() < ignitionCooldown then
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
      if be:getPlayerVehicleID(0) ~= info.vehId then gameplay_walk.getInVehicle(vehicle) end
      core_vehicleBridge.executeAction(vehicle, "setFreeze", false)
      listing.markedSold, listing.soldViewCounter = true, 1
      begin(vehicle, activeDrive and "testDrive" or "inspection", seller, info.value, delay, dealer.associatedOrganization)
      count("stolen")
      if result and not result.skipped and result.misses == 0 then count("cleanBypass") end
      grantXp(activeDrive and 20 or 15, "Dealership vehicle theft")
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
    gameplay_walk.getInVehicle(vehicle)
    if not gameplay_traffic.getTrafficData()[id] then gameplay_traffic.insertTraffic(id, true, true) end
    begin(vehicle, "street", nil, 0, delay, nil, result.skipped)
    count("stolen")
    if result.skipped then
      if fromTraffic then count("carjacked") end
      grantXp(12, "Vehicle theft")
    else
      if result.misses == 0 then count("cleanBypass") end
      grantXp(result.misses == 0 and 20 or 15, "Vehicle theft")
    end
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
  if case.phase ~= "stored" or case.seizure then return end
  local value = currentValue(case)
  local fee = identityFee(value)
  if not charge(fee, "Vehicle identity change", "service", false) then notify("Insufficient funds.") return end
  case.value = math.max(case.value, value)
  local seconds = perk("identityTime", 150)
  case.phase, case.readyAt = "workshop", os.time() + seconds
  save()
  notify(string.format("Identity change started. Cost: %s. Ready in %d seconds.", money(fee), seconds))
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
      "It'll be in pieces by tonight. That's what it's worth to me."}},
  exporter = {label = "Exporter", price = 0.97, patience = 1.15,
    quotes = {"Container leaves Thursday. I can make room for it.", "Overseas buyers like this model. Fair price.",
      "Clean paperwork? Then we can talk."}},
  racer = {label = "Street racer", price = 0.92, patience = 0.85,
    quotes = {"Does it pull? I'll take it if it pulls.", "Need something nobody knows for Friday night.",
      "Cash now if you don't ask what it's for."}},
  fixer = {label = "Fixer", price = 0.9, patience = 1.0,
    quotes = {"I have a client. I take my cut, you take yours.", "Quiet deal, quiet money.",
      "My people don't haggle long. Neither should you."}},
}
local buyerArchetypeKeys = {"chopShop", "exporter", "racer", "fixer"}
local buyerNames = {"Sly", "Dutch", "Moth", "Kestrel", "Rook", "Nico", "Viper", "Ghost", "Tank", "Mickey",
  "Juno", "Rafa", "Lazlo", "Pike", "Vera", "Bones", "Ox", "Silk", "Marek", "Duke"}

local function roundPrice(value)
  return math.max(50, math.floor((tonumber(value) or 0) / 50 + 0.5) * 50)
end

-- What the underground pays for this car; a freshly reported car is "hot" and worth less.
local function undergroundValue(case)
  local hot = os.time() < (case.reportAt or 0) + 360
  return math.floor(currentValue(case) * (hot and 0.54 or 0.61) * perk("fenceValue", 1)), hot
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
  local base = undergroundValue(case)
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
  local offer = {
    id = newOfferId(listing),
    buyer = buyerNames[math.random(1, #buyerNames)],
    archetype = key,
    value = roundPrice(value),
    createdAt = now,
    expiresAt = now + math.random(offerTtlRange[1], offerTtlRange[2]),
    quote = archetype.quotes[math.random(1, #archetype.quotes)],
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

-- Hands the car over at the agreed price. Returns "sold", "raided" or nil when it cannot happen now.
local function completeUndergroundSale(case, price, negotiated)
  price = math.floor(tonumber(price) or 0)
  if price <= 0 or not vehicleCase(case.inventoryId) or case.seizure then return end
  if repainted(case) == false and math.random() < paintStingChance() then
    seize("The buyer's contact matched the paint to the theft report and police raided the handover.")
    lastResult = {kind = "raided"}
    return "raided"
  end
  exitVehicle(inventory().getVehicleIdFromInventoryId(case.inventoryId))
  if inventory().removeVehicle(case.inventoryId) == false then
    notify("The vehicle cannot be handed over right now.")
    return
  end
  if case.source == "testDrive" then
    state.citations[#state.citations + 1] = {due = os.time() + 150, amount = fineFor(case)}
  end
  state.case, liveId = nil, nil
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

local function sellableCase()
  local case = state and state.case
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
  local case = state.case
  if not case then return view end
  local now = os.time()
  local record = case.inventoryId and inventory().getVehicles()[case.inventoryId]
  local vehicle = {phase = case.phase, identity = case.identity, source = case.source, repainted = repainted(case)}
  if record then
    vehicle.name = record.niceName
    vehicle.thumbnail = inventory().getVehicleThumbnail and inventory().getVehicleThumbnail(case.inventoryId)
  end
  if case.phase == "workshop" then vehicle.workshopRemaining = math.max(0, (case.readyAt or now) - now) end
  if case.inventoryId and record then
    local base, hot = undergroundValue(case)
    vehicle.marketValue, vehicle.hot, vehicle.suggestedPrice = base, hot, roundPrice(base)
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

function M.undergroundList(price)
  if not load() then return end
  local case = state.case
  if not case or case.phase ~= "ready" or not vehicleCase(case.inventoryId) or case.seizure then return end
  price = roundPrice(price)
  local now = os.time()
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
  scheduleNextOffer(case.listing, undergroundValue(case), os.time())
  save()
  publishUnderground()
end

function M.undergroundAccept(offerId)
  if not load() then return end
  local case = sellableCase()
  local offer = findOffer(case, tonumber(offerId))
  if not offer or offer.expiresAt <= os.time() then return end
  negotiation = nil
  completeUndergroundSale(case, offer.value)
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
  if not offer or offer.expiresAt <= os.time() then return end
  local base = undergroundValue(case)
  local archetype = buyerArchetypes[offer.archetype] or buyerArchetypes.fixer
  local asking = math.max(case.listing.price, offer.value)
  negotiation = {
    offerId = offer.id, opponentName = offer.buyer .. " (" .. (archetype.label or "Buyer") .. ")",
    quote = offer.quote, archetype = archetype, patience = 1, token = (negotiation and negotiation.token or 0) + 1,
    theirOffer = offer.value, myOffer = asking, startingPrice = asking, marketValue = base,
    maxBuyerPrice = math.max(base * 1.12, offer.value * 1.2), status = "initial",
    history = {{myOffer = asking, negotiationStatus = "initial"}, {theirOffer = offer.value, negotiationStatus = "initial"}},
  }
  publishUnderground()
end

local function settleNegotiationSale(n, price)
  local case = sellableCase()
  local opening = n.history[2] and n.history[2].theirOffer or price
  local outcome = case and completeUndergroundSale(case, price, price > opening)
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
    n.patience = math.max(0, n.patience - sellingPatienceDrop(n.myOffer, n.marketValue, n.archetype))
    if n.patience <= 0 then
      n.status = "failed"
      local case = sellableCase()
      if case then removeOffer(case, n.offerId); save() end
    else
      local counter = buyerCounter(n.myOffer, n.theirOffer, n.maxBuyerPrice)
      if counter >= n.myOffer then
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

function M.onOverhaulComputerAddFunctions(menu, buttons)
  if not load() then return end
  local case = state.case
  if not case or not case.inventoryId or not vehicleCase(case.inventoryId) or case.seizure then return end
  local row = buttons.vehicleSpecific[case.inventoryId]
  if not row then return end
  -- RLS calls callback() unconditionally if a click gets through, so even a disabled row needs one.
  local function info(label)
    row.rlsTheft = {id = "rlsTheft", label = label, order = 80, disabled = true, callback = function() end}
  end
  if case.phase == "stored" then
    row.rlsTheft = {id = "rlsTheft", order = 80,
      label = "Change vehicle identity (" .. money(identityFee(currentValue(case))) .. ")",
      callback = function()
        if state and state.case == case and vehicleCase(case.inventoryId) then
          startIdentity(case)
          overhaul_career_career.closeAllMenus()
        end
      end}
  elseif case.phase == "workshop" then
    info("Identity change in progress")
  elseif case.phase == "ready" then
    info("Ready to sell: list it in the Underground phone app")
  elseif case.phase == "listed" then
    info("Listed in the Underground phone app")
  end
end

local function updateCase(now)
  local case = state.case
  if not case then return end
  if case.seizure then
    if not case.inventoryId or not vehicleCase(case.inventoryId)
      or overhaul_career_logistics_general.canRemoveLogisticsVehicle(case.inventoryId) then
      seize(case.seizure)
    end
    return
  end
  if case.inventoryId and not vehicleCase(case.inventoryId) then
    charge(fineFor(case), "Missing stolen vehicle", "fine", true)
    state.case, liveId = nil, nil
    save()
    return
  end
  if case.phase == "transit" and not liveId then
    state.case = nil
    charge(fineFor(case), "Unresolved vehicle theft", "fine", true)
    save()
    notify("The unstored vehicle was recovered and a theft fine was charged.")
    return
  end
  if case.phase == "workshop" and now >= case.readyAt then
    local id = case.inventoryId
    case.identity = string.format("GX%06d", case.serial % 1000000)
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
  local stolen = case.phase == "transit" and liveId and getObjectByID(liveId)
  if stolen and ownedGarageNear(stolen) then
    if be:getPlayerVehicleID(0) == liveId then
      ui_message("Stolen vehicle: park inside the garage, then press Ctrl+Shift+J or get out to store it.",
        2, "rlsVehicleTheftStore")
    elseif gameplay_walk.isWalking() and store(stolen, true) then
      return
    end
  end

  -- After the identity change only an unrepainted car can still be matched to the theft report.
  if case.identity and repainted(case) ~= false then return end
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
  local patrolId = police.getNearestPoliceVehicle(id, true, true)
  local patrol = patrolId and getObjectByID(patrolId)
  if patrol and distance(patrol, vehicle) <= 160 then
    if not case.identity then
      police.setPursuitMode(1, id, {patrolId})
    elseif case.sightedPatrol ~= patrolId then
      -- New plate, reported paint: each patrol gets one look at the car.
      case.sightedPatrol = patrolId
      if math.random() < paintRecognitionChance() then
        notify("A patrol recognized the stolen vehicle by its original paint.")
        police.setPursuitMode(1, id, {patrolId})
      end
      save()
    end
  end
end

function M.onUpdate(dtReal, dt)
  if not load() then
    ignition = nil
    return
  end
  if ignition then updateIgnition(dtReal) end
  updateStarter(dtReal)
  if attempted then updateAttempt(dt) end
  -- The app's countdowns (identity change, next offer, offer expiry) are real-time, so refresh the open
  -- app on real time too: a paused or slowed simulation must not freeze them.
  appTick = appTick - dtReal
  if appOpen and appTick <= 0 then
    appTick = 1
    publishUnderground()
  end
  patrolCheck = patrolCheck - dt
  if patrolCheck > 0 then return end
  patrolCheck = 1
  bindRls()
  local now = os.time()
  for i = #state.citations, 1, -1 do
    local citation = state.citations[i]
    if now >= citation.due then
      table.remove(state.citations, i)
      charge(citation.amount, "Dealership test-drive investigation", "fine", true)
      notify("Test-drive investigation closed. Fine: " .. money(citation.amount))
      save()
    end
  end
  updateCase(now)
end

function M.onPursuitAction(id, action)
  if not state or not state.case then return end
  local arrestedCase = state.case
  local vehicleId = arrestedCase.inventoryId and inventory().getVehicleIdFromInventoryId(arrestedCase.inventoryId) or liveId
  if id ~= vehicleId then return end
  if action == "evade" then
    arrestedCase.patrolCooldownUntil = os.time() + 45
    arrestedCase.evades = (arrestedCase.evades or 0) + 1
    count("evaded")
    if arrestedCase.evades <= 3 then grantXp(10, "Police evaded in a stolen vehicle") end
    save()
  elseif action == "arrest" then
    -- Defer object removal until RLS has finished its own arrest handler.
    core_jobsystem.create(function(job)
      job.sleep(0.1)
      if state and state.case == arrestedCase and (liveId == id or
        (state.case.inventoryId and inventory().getVehicleIdFromInventoryId(state.case.inventoryId) == id)) then
        seize("Police identified the stolen vehicle.")
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
  forcedStops = {}
end

function M.onClientEndMission()
  attempted, liveId, ignition, starter = nil, nil, nil, nil
  forcedStops = {}
end

function M.onExtensionUnloaded()
  for key, entry in pairs(bindings) do
    if entry.owner[key] == entry.wrapper then entry.owner[key] = entry.original end
  end
end

return M
