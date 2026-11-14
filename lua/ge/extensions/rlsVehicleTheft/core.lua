-- Shared basics every part uses: the play-time clock, messages, money, the saved career data
-- (load and save) and a few world helpers.

return function(ctx)
  local session = ctx.session
  local config = ctx.config
  local heatHotSeconds, heatWarmSeconds, offerChannel, rules, saveFile, undergroundAppId =
    config.heatHotSeconds, config.heatWarmSeconds, config.offerChannel, config.rules, config.saveFile, config.undergroundAppId

  -- Play time in seconds. Every saved timer (reports, heat, workshop jobs, offers, bans, investigations) is
  -- measured against it. It runs on real time while the career is loaded, so a paused simulation or an open
  -- phone does not freeze the countdowns, but it stops while the game is closed.
  local function gameTime()
    return session.state and session.state.clock or 0
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
    if name ~= session.profile then
      session.profile = name
      session.state = jsonReadFile(path .. saveFile) or {}
      session.state.bans = session.state.bans or {}
      session.state.citations = session.state.citations or {}
      session.state.serial = session.state.serial or 0
      session.state.cases = session.state.cases or {}
      -- Before 0.9 timers were wall-clock (os.time); starting the play-time clock there keeps them valid.
      session.state.clock = tonumber(session.state.clock) or os.time()
      -- A saved undercover operation survives the reload, but the vehicle it was chasing does not.
      if session.state.sting then session.state.sting.pursuing = nil end
      -- Before 0.8 a profile held a single case in state.case; it becomes the first entry of the list.
      if session.state.case then
        table.insert(session.state.cases, session.state.case)
        session.state.case = nil
      end
      for _, case in ipairs(session.state.cases) do
        -- Before 0.6 a single offer was requested at the garage computer; those cases go back to "ready"
        -- so the vehicle can be listed in the Underground phone app.
        if case.phase == "offer" then case.phase, case.offer, case.expiresAt = "ready", nil, nil end
        -- Older cases used one six-minute hot window tied directly to the expected report time.
        -- Preserve that window while splitting it into a hot and warm stage.
        local reportAt = case.reportAt or gameTime()
        case.heatHotUntil = case.heatHotUntil or (reportAt + heatHotSeconds)
        case.heatWarmUntil = case.heatWarmUntil or (reportAt + heatHotSeconds + heatWarmSeconds)
      end
      session.attempted, session.liveId, session.patrolCheck = nil, nil, 0
      session.negotiation, session.lastResult, session.selectedSerial = nil, nil, nil
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

  -- RLS leaves the arrested player seated; deleting a vehicle with the player inside strands them.
  -- Mirror RLS's own removal path and put the player on foot first.
  local function exitVehicle(vehId)
    if vehId and be:getPlayerVehicleID(0) == vehId and gameplay_walk and not gameplay_walk.isWalking() then
      gameplay_walk.setWalkingMode(true, nil, nil, true)
    end
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

  -- channel: one of the app's notification channels (rls-underground.json), offers by default.
  -- kind: RLS phone card style (success, warning, error, invite, info).
  local function notifyPhone(title, message, channel, kind)
    if not overhaul_phone_apps_layout then pcall(extensions.load, "overhaul_phone_apps_layout") end
    local layout = overhaul_phone_apps_layout
    if not (layout and layout.fireNotification) then return end
    pcall(layout.fireNotification, channel or offerChannel,
      {title = title, message = message, kind = kind or "invite", ttl = 8, source = "Underground"},
      {appId = undergroundAppId})
  end

  ctx.accessDistance = accessDistance
  ctx.charge = charge
  ctx.distance = distance
  ctx.exitVehicle = exitVehicle
  ctx.fineFor = fineFor
  ctx.gameTime = gameTime
  ctx.inventory = inventory
  ctx.keyLabel = keyLabel
  ctx.load = load
  ctx.money = money
  ctx.notify = notify
  ctx.notifyPhone = notifyPhone
  ctx.parkedCars = parkedCars
  ctx.save = save
  ctx.walkingPlayer = walkingPlayer

  return function() end -- uses nothing from the other parts
end
