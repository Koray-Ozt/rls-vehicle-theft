-- Keeps the road full: every car taken from traffic is replaced by a new one, and the traffic
-- hooks log what joins and leaves.

return function(ctx)
  local M = ctx.M
  local session = ctx.session

  -- Traffic top-up. Taking a car out of traffic (removeTraffic) shrinks the traffic for good: the game never
  -- refills it, so every theft left one car fewer until only police cars (which cannot be stolen) remained.
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

  -- One-time hint: with little traffic there are few cars to take, so point to the traffic setting. The mod does
  -- not change the setting itself. Shown once per save, shortly after the replacement car joins the road.
  local lowTrafficStandard = 4
  local trafficHintDue = false

  local function standardTrafficCount()
    local count = 0
    for _, entry in pairs(gameplay_traffic.getTrafficData()) do
      if entry.isAi and not entry.reserved and not entry.isTaxi and entry.role and entry.role.name == "standard" then
        count = count + 1
      end
    end
    return count
  end

  local function showTrafficHint()
    trafficHintDue = false
    if not session.state or session.state.trafficHint then return end
    session.state.trafficHint = true
    ui_message("There are few cars on the road, so few to take. You can raise the traffic amount in "
      .. "Options > Gameplay > Traffic.", 10, "rlsVehicleTheftTraffic")
    trafficLog("shown traffic setting hint")
  end

  local function resetTrafficTopUp()
    trafficOwed, trafficRespawnAt, trafficSpawnPending, trafficFailures = 0, 0, nil, 0
    stolenTraffic = {}
    trafficHintDue = false
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

  -- Traffic hooks, used for the top-up and for the log: every car that leaves or joins traffic is recorded,
  -- so a drop that is not a theft shows up as "removed (other)".
  function M.onTrafficVehicleRemoved(id)
    if not session.state then return end
    local theft = stolenTraffic[id]
    stolenTraffic[id] = nil
    trafficLog("traffic car " .. tostring(id) .. " removed (" .. (theft and "theft" or "other") .. ")")
  end

  function M.onTrafficVehicleAdded(id)
    if not session.state then return end
    if session.ignoreTrafficAdd == id then
      session.ignoreTrafficAdd = nil
      return
    end
    if trafficSpawnPending then
      trafficSpawnPending = nil
      trafficLog("replacement car " .. tostring(id) .. " joined traffic")
      if trafficHintDue then showTrafficHint() end
    end
  end

  -- Traffic was switched off: nothing is owed any more.
  function M.onTrafficStopped()
    if trafficOwed > 0 then trafficLog("traffic stopped, dropping owed cars") end
    resetTrafficTopUp()
  end

  -- A car the player takes out of traffic: log it, owe the road a replacement car and, on a quiet road, queue
  -- the one-time traffic hint. Must be called while the car is still in traffic.
  local function takeFromTraffic(id)
    local wasTraffic = gameplay_traffic.getTrafficData()[id] ~= nil
    trafficLog("theft, before removing traffic car " .. id)
    if wasTraffic and not session.state.trafficHint and standardTrafficCount() <= lowTrafficStandard then
      trafficHintDue = true
    end
    stolenTraffic[id] = true
    gameplay_traffic.removeTraffic(id)
    if wasTraffic then trafficOwed = math.min(trafficMaxOwed, trafficOwed + 1) end
  end

  ctx.resetTrafficTopUp = resetTrafficTopUp
  ctx.takeFromTraffic = takeFromTraffic
  ctx.updateTrafficTopUp = updateTrafficTopUp

  return function() end -- uses nothing from the other parts
end
