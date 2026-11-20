-- Custody after a theft arrest (docs/proposals/arrest-custody-prison.md): the player is taken off the street,
-- every stolen car the police can link to a theft report is seized, the player is booked at the police
-- station, sentenced, serves the sentence and is released on foot.
--
-- Only arrests that confirm a theft lead here: the police identified a stolen car (patrol pursuit) or caught
-- the seller of an undercover sting (arrestForTheft). RLS has already charged its own pursuit fine. The theft
-- fines are not charged with the seizures but at sentencing, where the lawyer can lower them.
--
-- The search: the arrested car and every other case that is not fully disguised (new plate and paint) become
-- counts. Open dealership investigations are closed into the same sentence. The counts are saved before any
-- car is seized ("count first, seize second"), and the seizures run again on resume: a seized case is gone
-- from state.cases, so each car is taken once and each fine counted once.
--
-- state.custody is one saved record that moves through three stages:
--   transfer    BUSTED screen, the cars are seized, the player is put on foot and moved to the station
--   sentencing  the custody screen offers a public defender or a private lawyer
--   serving     the fine and fee are paid and the clocks moved forward; a short wait, then release
-- Choosing a lawyer pays, advances the mod's play clock and enters "serving" in one save, so nothing is paid
-- twice. The RLS world clock is moved once (custody.timeAdvanced is saved first). Any stage interrupted by a
-- reload, level change or profile switch resumes on the next load.
--
-- The custody screen (Custody.vue) only draws what Lua sends it: a view with a stage and the numbers to show.

return function(ctx)
  local M = ctx.M
  local session = ctx.session
  local custodyConfig = ctx.config.custody
  local sentenceConfig, lawyers = custodyConfig.sentence, custodyConfig.lawyers
  local viewEvent = "RlsTheftCustody"
  -- From the other parts; bound by the function this file returns once every part is installed.
  local charge, disguised, dropIgnition, exitVehicle, findCase, fineFor, gameTime, inventory, money,
    publishUnderground, releaseForcedStop, save, seize
  local searchMessage = "Police searched your garages and seized another stolen car."

  local runToken = 0

  -- Its own message category, so the release note does not replace the seizure message.
  local function notifyCustody(message)
    ui_message(message, 10, "rlsVehicleTheftCustody")
  end

  local function trace(message)
    log("I", "rlsVehicleTheft", "custody: " .. message)
  end

  local function round(value, step)
    step = step or 1
    return math.floor((tonumber(value) or 0) / step + 0.5) * step
  end

  local function hoursLabel(hours)
    local days, rest = math.floor(hours / 24), hours % 24
    if days == 0 then return string.format("%d h", hours) end
    return rest == 0 and string.format("%d d", days) or string.format("%d d %d h", days, rest)
  end

  local function playerMoney()
    local attributes = overhaul_career_economy_playerAttributes
    return attributes and tonumber(attributes.getAttributeValue("money")) or 0
  end

  -- Release point -----------------------------------------------------------------------------------

  local function toVec(t)
    if type(t) == "table" and tonumber(t[1]) and tonumber(t[2]) and tonumber(t[3]) then
      return vec3(tonumber(t[1]), tonumber(t[2]), tonumber(t[3]))
    end
  end

  -- A station is either a fixed position (pos, optional facing dir) or a parking spot in a sites file.
  local function readSpot(station)
    if station.pos then return toVec(station.pos) end
    local sites = station.sitesFile and jsonReadFile(station.sitesFile)
    for _, spot in ipairs(sites and sites.parkingSpots or {}) do
      if spot.name == station.spot and type(spot.pos) == "table" and #spot.pos == 3 then
        return vec3(spot.pos[1], spot.pos[2], spot.pos[3])
      end
    end
  end

  -- Where the player is released: the map's police station when one is known, otherwise the closest garage.
  -- Returns position, label, isStation, facing direction (or nil); nil when the map has neither.
  local function resolveRelease(levelName)
    local station = custodyConfig.stations[levelName or ""]
    local pos = station and readSpot(station)
    if pos then return pos, station.label, true, toVec(station.dir) end
    if station then trace("station spot " .. tostring(station.spot) .. " not found in " .. tostring(station.sitesFile)) end
    local player = getPlayerVehicle(0)
    local garage = inventory().getClosestGarage(player and player:getPosition() or nil, levelName)
    local door = garage and overhaul_world_facilities.getAverageDoorPositionForFacility(garage)
    if door then return door, "the nearest garage", false end
  end

  -- Puts the player on foot (never in the seized or frozen car) and moves them to the release point.
  -- Returns the label and isStation of where they are now; no label means they stayed where they were.
  local function moveToRelease(job, current)
    exitVehicle(be:getPlayerVehicleID(0))
    local waited = 0
    while not gameplay_walk.isWalking() and waited < 3 do
      job.sleep(0.1)
      waited = waited + 0.1
    end
    if not current() then return end
    local pos, label, isStation, dir = resolveRelease(getCurrentLevelIdentifier())
    local player = getPlayerVehicle(0)
    if not (pos and player and gameplay_walk.isWalking()) then
      trace(string.format("no release point (position %s, player %s, walking %s)", tostring(pos ~= nil),
        tostring(player ~= nil), tostring(gameplay_walk.isWalking())))
      return nil, false
    end
    local ok, placed = pcall(spawn.safeTeleport, player, pos)
    if not ok or placed == false then
      trace("teleport to " .. tostring(label) .. " failed: " .. tostring(placed))
      return nil, false
    end
    if dir and gameplay_walk.setRot then pcall(gameplay_walk.setRot, dir, vec3(0, 0, 1)) end
    return label, isStation
  end

  -- Sentence ----------------------------------------------------------------------------------------

  local chargeLabels = {
    street = "Vehicle theft",
    inspection = "Theft of a dealership car",
    testDrive = "Theft of a test-drive car",
  }

  local function chargeLabel(count)
    local label = count.taxi and "Taxi theft" or chargeLabels[count.source] or chargeLabels.street
    if count.sting then label = label .. ", sold to an undercover officer" end
    return label
  end

  -- The count the arrest itself was for; the others were found in the search.
  local function mainCount(custody)
    for _, count in ipairs(custody.counts) do
      if count.arrested then return count end
    end
    return custody.counts[1]
  end

  local function baseHours(count)
    local base = sentenceConfig.baseHours[count.source] or sentenceConfig.baseHours.street
    return count.taxi and math.max(base, sentenceConfig.taxiHours) or base
  end

  -- What the court hands down before a lawyer works on it, in game hours: the arrested car with the prior
  -- arrests, its evades and a sting; each car found in the search adds extraCarFactor of its own base.
  local function sentenceHours(custody, priors)
    local main = mainCount(custody)
    local factor = 1 + sentenceConfig.priorFactor * math.min(priors, sentenceConfig.maxPriors)
      + sentenceConfig.evadeFactor * math.min(main.evades or 0, sentenceConfig.maxEvades)
    local hours = math.ceil(baseHours(main) * factor) + (main.sting and sentenceConfig.stingHours or 0)
    for _, count in ipairs(custody.counts) do
      if count ~= main then hours = hours + math.ceil(baseHours(count) * sentenceConfig.extraCarFactor) end
    end
    return math.max(1, math.min(sentenceConfig.maxHours, hours))
  end

  local function totalFine(custody)
    local fine = tonumber(custody.investigations) or 0
    for _, count in ipairs(custody.counts) do fine = fine + (tonumber(count.fine) or 0) end
    return fine
  end

  local function caseName(case)
    local record = case.inventoryId and inventory().getVehicles()[case.inventoryId]
    local name = record and record.niceName or case.scrapName
    return type(name) == "string" and name or nil
  end

  local function countFor(case, arrested, sting)
    return {serial = case.serial, source = case.source, taxi = case.taxi or nil, sting = sting or nil,
      evades = math.min(tonumber(case.evades) or 0, sentenceConfig.maxEvades), name = caseName(case),
      fine = fineFor(case), arrested = arrested or nil}
  end

  -- Seizes every counted case still open. Safe to run again: a seized case has left state.cases, and one RLS
  -- holds back keeps fineDeferred, so it is never fined outside the sentence.
  local function confiscate(custody)
    for _, count in ipairs(custody.counts) do
      local case = count.serial and findCase(count.serial)
      if case then seize(count.arrested and custody.message or searchMessage, case, true) end
    end
    -- What hung on a seized case goes with it.
    local n = session.negotiation
    if n and not findCase(n.serial) then session.negotiation = nil end
    local sting = session.state.sting
    if sting and not findCase(sting.serial) then session.state.sting = nil end
    save()
    pcall(publishUnderground)
  end

  -- Whatever the player was doing on the street stops with the arrest.
  local function cancelInteractions()
    if session.attempted then
      pcall(releaseForcedStop, session.attempted.id)
      session.attempted = nil
    end
    session.scrapDialog = nil
    dropIgnition()
  end

  -- What a lawyer (lawyers[id]) makes of the sentence: hours, fine, fee and whether the player can pay the fee.
  local function optionFor(custody, id)
    local lawyer = lawyers[id]
    if not lawyer then return nil end
    local sentence = custody.sentence
    local fee = 0
    if lawyer.feeShare then
      fee = math.max(lawyer.feeMinimum, round(sentence.fine * lawyer.feeShare + sentence.hours * lawyer.feePerHour, 50))
    end
    return {id = id, label = lawyer.label, note = lawyer.note, fee = fee,
      hours = math.max(1, math.ceil(sentence.hours * lawyer.hours)),
      fine = round(sentence.fine * lawyer.fine), affordable = fee == 0 or playerMoney() >= fee}
  end

  -- Play-clock seconds per game hour: the mod's timers (heat, workshop jobs, offers, bans) run on real play
  -- time, so a sentence moves them as far as the same span of game time takes to play.
  local function clockSecondsPerHour()
    local weather = overhaul_world_weather
    local dayMinutes = weather and weather.getDayLengthMinutes and tonumber(weather.getDayLengthMinutes())
    return (dayMinutes or custodyConfig.fallbackDayMinutes) * 60 / 24
  end

  -- Moves the RLS world clock forward. Dynamic weather owns the day count, and its sleepTo moves to the next
  -- time of day it is given, so long sentences go in steps of at most half a day (a full-day step could land
  -- on the current minute and move by almost nothing). Without dynamic weather only the time of day moves.
  local function advanceWorldTime(hours)
    local remaining = math.floor(hours * 60 + 0.5)
    local weather = overhaul_world_weather
    local external = weather and weather.isExternalOverrideActive and weather.isExternalOverrideActive()
    local calendar = weather and not external and weather.sleepTo and weather.getCalendarState
      and weather.getCalendarState()
    if calendar and calendar.ready then
      local minute = tonumber(calendar.minuteOfDay) or 0
      while remaining > 0 do
        local step = math.min(remaining, 720)
        minute = (minute + step) % 1440
        local ok, moved = pcall(weather.sleepTo, (minute / 1440 + 0.5) % 1)
        if not ok or moved ~= true then
          trace("dynamic weather did not move the clock: " .. tostring(moved))
          break
        end
        remaining = remaining - step
      end
      if remaining == 0 then return "dynamic" end
    end
    local tod = scenetree and scenetree.tod
    if not tod or tod.time == nil then
      trace("no clock to advance")
      return nil
    end
    local time = (tod.time + remaining / 1440) % 1
    tod.time = time
    if core_environment and core_environment.getTimeOfDay and core_environment.setTimeOfDay then
      local state = core_environment.getTimeOfDay() or {}
      state.time = time
      pcall(core_environment.setTimeOfDay, state)
    end
    return "timeOfDay"
  end

  -- Takes a lawyer: pays the fine and fee, moves the play clock by the sentence and enters "serving", in one
  -- save. The public defender is always possible; a private lawyer needs the fee in hand.
  local function choose(custody, id)
    if custody.stage == "serving" then return false end
    local option = optionFor(custody, id)
    if not option or not option.affordable then return false end
    custody.stage = "serving"
    custody.choice = {lawyer = id, hours = option.hours, fine = option.fine, fee = option.fee}
    if option.fine > 0 then charge(option.fine, "Vehicle theft fine", "fine", true) end
    if option.fee > 0 then charge(option.fee, "Private lawyer", "service", true) end
    session.state.clock = session.state.clock + option.hours * clockSecondsPerHour()
    save()
    trace(string.format("sentenced with %s: %d h, fine %d, fee %d", id, option.hours, option.fine, option.fee))
    return true
  end

  -- Records the arrest and returns how many arrests came before it within the record window (play time,
  -- which the sentences themselves move forward).
  local function recordArrest(now)
    local record = session.state.record or {}
    local recent = {}
    for _, at in ipairs(type(record.recent) == "table" and record.recent or {}) do
      if tonumber(at) and now - at < sentenceConfig.priorWindowSeconds then recent[#recent + 1] = at end
    end
    local priors = #recent
    recent[#recent + 1] = now
    session.state.record = {arrests = (tonumber(record.arrests) or 0) + 1, recent = recent}
    return priors
  end

  -- Views for the custody screen -------------------------------------------------------------------

  local function sentencingView(custody, run)
    local options = {}
    for _, id in ipairs({"public", "private"}) do options[#options + 1] = optionFor(custody, id) end
    local counts = {}
    for _, count in ipairs(custody.counts) do
      counts[#counts + 1] = {charge = chargeLabel(count), name = count.name, fine = tonumber(count.fine) or 0,
        arrested = count.arrested or false}
    end
    return {stage = "sentencing", place = run.label, counts = counts, investigations = tonumber(custody.investigations) or 0,
      priors = custody.priors or 0, evades = mainCount(custody).evades or 0, options = options}
  end

  local function releaseMessage(custody, label, isStation)
    local where = isStation and ("at " .. label) or label and ("near " .. label) or "where you were arrested"
    local prefix = (label and not isStation) and "This map has no police station on record. " or ""
    local seized = #custody.counts > 1 and string.format(" %d stolen cars were seized.", #custody.counts) or ""
    local choice = custody.choice
    if not choice then return prefix .. "You were booked and released " .. where .. "." .. seized end
    local paid = choice.fine > 0 and ("Fine: " .. money(choice.fine)) or "No fine"
    if choice.fee > 0 then paid = paid .. ", lawyer: " .. money(choice.fee) end
    return string.format("%sSentence served: %s. You were released %s. %s.%s", prefix, hoursLabel(choice.hours), where,
      paid, seized)
  end

  local function release(custody, label, isStation)
    session.state.custody = nil
    save()
    trace(string.format("released at %s after %s", tostring(label), tostring(custody.reason)))
    notifyCustody(releaseMessage(custody, label, isStation))
  end

  -- The custody screen. Falls back to the game's fade screen with a BUSTED title if the route cannot open;
  -- the public defender then takes the case, since there is nothing to choose on.
  local function openScreen()
    local ok, opened = pcall(extensions.ui_router.navigate, custodyConfig.route)
    if ok and opened ~= false then return true end
    trace("custody screen did not open: " .. tostring(opened))
    if ui_fadeScreen then ui_fadeScreen.start(custodyConfig.fadeSeconds, {title = "BUSTED"}) end
    return false
  end

  -- Runs the custody record from whatever stage it is in. One run at a time.
  local function runCustody(resumed)
    local custody = session.state and session.state.custody
    if not custody or session.custodyJob then return end
    -- Phase 1 saves had no stage or sentence, Phase 2 saves a single offense instead of counts.
    custody.stage = custody.stage or "transfer"
    if not custody.counts then
      local offense = custody.offense or {source = "street", fine = 0}
      offense.arrested = true
      custody.counts, custody.offense = {offense}, nil
    end
    custody.sentence = custody.sentence
      or {hours = sentenceHours(custody, custody.priors or 0), fine = totalFine(custody)}
    runToken = runToken + 1
    local run = {token = runToken}
    session.custodyJob = run
    local fade = custodyConfig.fadeSeconds
    local function current() return session.custodyJob == run and session.state and session.state.custody == custody end
    local function push(view)
      view.token = run.token
      session.custodyView = view
      guihooks.trigger(viewEvent, view)
    end
    local function hide(job)
      run.closing = true
      if run.overlay then
        push({stage = "leaving"})
        if job then job.sleep(fade) end
        pcall(extensions.ui_router.navigate, "play")
      elseif ui_fadeScreen then
        ui_fadeScreen.stop(fade)
      end
      session.custodyView = nil
      run.hidden = true
    end

    local function body(job)
      push({stage = "busted"})
      run.overlay = openScreen()
      job.sleep(fade + 0.2)
      if not current() then return end
      -- A resumed transfer finishes a search the game closing cut short.
      if resumed and custody.stage == "transfer" then confiscate(custody) end
      run.label, run.isStation = moveToRelease(job, current)
      if not current() then return end
      if custody.stage == "transfer" then
        job.sleep(math.max(0.3, custodyConfig.holdSeconds - fade))
        if not current() then return end
        custody.stage = "sentencing"
        save()
      end
      if custody.stage == "sentencing" then
        if run.overlay then
          push(sentencingView(custody, run))
          while current() and custody.stage == "sentencing" do
            if run.left then
              -- Something closed the screen (a menu, the back key): bring it back, the choice is still due.
              run.left = false
              job.sleep(0.3)
              if current() and custody.stage == "sentencing" then
                run.overlay = openScreen()
                if not run.overlay then choose(custody, "public") end
              end
            end
            job.sleep(0.1)
          end
          if not current() then return end
        else
          choose(custody, "public")
        end
      end
      if not custody.timeAdvanced then
        custody.timeAdvanced = true
        save()
        trace("world clock: " .. tostring(advanceWorldTime(custody.choice.hours)))
      end
      push({stage = "serving", hours = custody.choice.hours, seconds = custodyConfig.serveSeconds, place = run.label})
      job.sleep(custodyConfig.serveSeconds)
      hide(job)
      if current() then release(custody, run.label, run.isStation) end
    end

    core_jobsystem.create(function(job)
      local ok, err = pcall(body, job)
      if not ok then
        -- A failure must not leave the screen black, the player stuck in custody or the fine unpaid.
        trace("custody failed: " .. tostring(err))
        if not run.hidden then pcall(hide) end
        if current() then
          if custody.stage ~= "serving" then pcall(choose, custody, "public") end
          release(custody, run.label, run.isStation)
        end
      end
      if session.custodyJob == run then session.custodyJob = nil end
    end, 1)
  end

  -- Opens custody. counts: what the court judges, one per car ({serial, source, taxi, sting, evades, name,
  -- fine, arrested}); investigations: the closed dealership investigations' total; message: what the arrested
  -- car's seizure says. The counts are saved before the cars are seized. A second arrest while one is being
  -- processed is ignored.
  local function beginCustody(reason, counts, investigations, message)
    if not custodyConfig.enabled or not session.state then return false end
    if session.state.custody then
      trace("already in custody; ignored: " .. tostring(reason))
      return false
    end
    cancelInteractions()
    local now = gameTime()
    local priors = recordArrest(now)
    local custody = {reason = reason, at = now, level = getCurrentLevelIdentifier(), stage = "transfer",
      counts = counts, investigations = investigations or 0, message = message, priors = priors}
    custody.sentence = {hours = sentenceHours(custody, priors), fine = totalFine(custody)}
    session.state.custody = custody
    save()
    trace(string.format("taken into custody: %s (%d cars, %d prior arrests)", tostring(reason), #counts, priors))
    confiscate(custody)
    runCustody()
    return true
  end

  -- An arrest that confirms a theft. With custody on, the police search: the arrested car and every other
  -- case they can still link to a theft report (not fully disguised) are counted and seized, their fines left
  -- for the sentence, and open dealership investigations are closed into it. sting: the seller of an
  -- undercover sting was caught. A case already waiting for a seizure without a deferred fine is left alone:
  -- it is fined when that seizure completes.
  local function arrestForTheft(message, case, reason, sting)
    if not custodyConfig.enabled or not session.state or session.state.custody then
      seize(message, case)
      return false
    end
    local counts = {countFor(case, true, sting)}
    for _, other in ipairs(session.state.cases) do
      if other ~= case and not disguised(other) and not (other.seizure and not other.fineDeferred) then
        counts[#counts + 1] = countFor(other)
      end
    end
    local investigations = 0
    for _, citation in ipairs(session.state.citations) do investigations = investigations + (tonumber(citation.amount) or 0) end
    session.state.citations = {}
    return beginCustody(reason, counts, investigations, message)
  end

  -- Every second: finish custody a reload or level change interrupted, once the player is back in the world.
  local function updateCustody()
    if not session.state.custody or session.custodyJob then return end
    if not getPlayerVehicle(0) or not gameplay_walk then return end
    if core_gamestate and core_gamestate.getLoadingStatus and core_gamestate.getLoadingStatus("careerVehicles") then return end
    trace("resuming custody at stage " .. tostring(session.state.custody.stage))
    runCustody(true)
  end

  local function inCustody()
    return session.state ~= nil and session.state.custody ~= nil
  end

  -- The custody screen's calls ---------------------------------------------------------------------

  function M.getCustodyView()
    return session.custodyJob and session.custodyView or nil
  end

  -- id: "public" or "private". Ignored unless it answers the sentencing view now on screen.
  function M.custodyChoose(token, id)
    local run, custody = session.custodyJob, session.state and session.state.custody
    if not run or run.token ~= token or not custody or custody.stage ~= "sentencing" then return false end
    return choose(custody, id)
  end

  -- The screen closed. Unless custody is ending, the run opens it again.
  function M.custodyScreenLeft(token)
    local run = session.custodyJob
    if run and run.token == token and not run.closing then run.left = true end
  end

  -- Console test: rlsVehicleTheft.debugCustody(). Runs custody for an imaginary $20,000 street car; there is
  -- no search, so the player's real cases and investigations are left alone.
  function M.debugCustody()
    if not ctx.load() then return "career not active" end
    local pos, label, isStation = resolveRelease(getCurrentLevelIdentifier())
    beginCustody("Console test.", {{source = "street", name = "Console test car", arrested = true,
      fine = fineFor({source = "street", value = 20000})}}, 0, "Console test.")
    return {level = getCurrentLevelIdentifier(), label = label, station = isStation, pos = pos and pos:toTable(),
      sentence = session.state.custody and session.state.custody.sentence}
  end

  -- Console helper for adding a station: stand where released players should appear, look the way they
  -- should face, run rlsVehicleTheft.debugPosition() and copy the line into config.custody.stations.
  function M.debugPosition()
    local player = getPlayerVehicle(0)
    if not player then return "no player" end
    local p = player:getPosition()
    local forward = core_camera and core_camera.getForward and core_camera.getForward() or vec3(0, 1, 0)
    local flat = math.sqrt(forward.x * forward.x + forward.y * forward.y)
    local dx, dy = flat > 0 and forward.x / flat or 0, flat > 0 and forward.y / flat or 1
    local line = string.format('%s = {label = "the police station", pos = {%.2f, %.2f, %.2f}, dir = {%.3f, %.3f, 0}},',
      getCurrentLevelIdentifier() or "map", p.x, p.y, p.z, dx, dy)
    log("I", "rlsVehicleTheft", "station: " .. line)
    return line
  end

  ctx.arrestForTheft = arrestForTheft
  ctx.beginCustody = beginCustody
  ctx.inCustody = inCustody
  ctx.resolveRelease = resolveRelease
  ctx.updateCustody = updateCustody

  return function()
    charge = ctx.charge
    disguised = ctx.disguised
    dropIgnition = ctx.dropIgnition
    exitVehicle = ctx.exitVehicle
    findCase = ctx.findCase
    fineFor = ctx.fineFor
    gameTime = ctx.gameTime
    inventory = ctx.inventory
    money = ctx.money
    publishUnderground = ctx.publishUnderground
    releaseForcedStop = ctx.releaseForcedStop
    save = ctx.save
    seize = ctx.seize
  end
end
