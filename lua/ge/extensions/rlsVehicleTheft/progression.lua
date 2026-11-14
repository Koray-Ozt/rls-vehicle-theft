-- Vehicle Theft skill: XP, level, perks, the theft counters and RLS milestones.

return function(ctx)
  local M = ctx.M
  local session = ctx.session
  local config = ctx.config
  local perkTiers, skillFile, skillKey =
    config.perkTiers, config.skillFile, config.skillKey
  -- From the other parts; bound by the function this file returns once every part is installed.
  local load, money

  -- Vehicle Theft is an RLS career skill (gameplay/overhaul/domains/careerSkills/skills/vehicleTheft/info.json).
  -- XP is the player attribute below; RLS shows levels, level-up celebrations and per-level milestones for it.
  -- Perks are step functions of the level and match the unlock cards in that file.

  local skillCurve

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
    session.state.stats = session.state.stats or {}
    local s = session.state.stats
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

  ctx.count = count
  ctx.decorateSkillsPage = decorateSkillsPage
  ctx.grantXp = grantXp
  ctx.perk = perk
  ctx.skillProgress = skillProgress

  return function()
    load = ctx.load
    money = ctx.money
  end
end
