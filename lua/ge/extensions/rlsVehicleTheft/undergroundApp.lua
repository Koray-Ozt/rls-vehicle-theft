-- The Underground phone app (ui UndergroundApp.vue): what it shows and the actions it calls.

return function(ctx)
  local M = ctx.M
  local session = ctx.session
  local config = ctx.config
  local heatMultipliers, undergroundEvent =
    config.heatMultipliers, config.undergroundEvent
  -- From the other parts; bound by the function this file returns once every part is installed.
  local buyerArchetypes, caseLimit, completeUndergroundSale, expensesFor, findCase, findOffer, gameTime,
    handoverBlocked, heatStatus, inCustody, inventory, load, paintStingChance, perk, removeOffer, repainted, roundPrice,
    save, scheduleNextOffer, skillProgress, undergroundValue, vehicleCase

  -- The case the Underground app is showing: the one the player picked, else the first stored car,
  -- else the car still being carried.
  local function selectedCase()
    local list = session.state and session.state.cases or {}
    local first
    for _, case in ipairs(list) do
      if case.serial == session.selectedSerial then return case end
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
    local n = session.negotiation
    if not n then return nil end
    return {
      offerId = n.offerId, opponentName = n.opponentName, quote = n.quote, patience = n.patience,
      history = n.history, status = n.status, theirOffer = n.theirOffer, myOffer = n.myOffer,
      startingPrice = n.startingPrice, marketValue = n.marketValue, result = n.result,
    }
  end

  function M.getUndergroundState()
    if not load() then return {available = false} end
    local view = {available = true, result = session.lastResult, negotiation = negotiationView(), offers = {}}
    view.skill = skillProgress()
    view.limit = caseLimit()
    -- The rates and risks the app explains, with the player's perks and open cases applied.
    local fence = perk("fenceValue", 1)
    view.rates = {}
    for stage, multiplier in pairs(heatMultipliers) do view.rates[stage] = math.floor(multiplier * fence * 100 + 0.5) end
    view.raidChance = math.floor(paintStingChance() * 100 + 0.5)
    view.cases = {}
    local now = gameTime()
    if session.state.sting then
      view.sting = {serial = session.state.sting.serial, chasing = session.state.sting.pursuing ~= nil,
        remaining = math.max(0, session.state.sting.untilAt - now)}
    end
    local case = selectedCase()
    for _, other in ipairs(session.state.cases) do
      local record = other.inventoryId and inventory().getVehicles()[other.inventoryId]
      local heat = heatStatus(other, now)
      table.insert(view.cases, {serial = other.serial, phase = other.phase,
        name = record and record.niceName or other.scrapName or "Stolen vehicle", selected = other == case, heatLabel = heat.label})
    end
    if not case then return view end
    local record = case.inventoryId and inventory().getVehicles()[case.inventoryId]
    local vehicle = {serial = case.serial, phase = case.phase, identity = case.identity, source = case.source,
      repainted = repainted(case)}
    if not record and case.scrapName then vehicle.name = case.scrapName end
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
    vehicle.expenses, vehicle.expensesPartial, vehicle.expensesIdentity, vehicle.expensesPaint = expensesFor(case)
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
    session.appOpen = open == true
    if session.appOpen then publishUnderground() end
  end

  function M.undergroundSelect(serial)
    if not load() or session.negotiation then return end
    if findCase(tonumber(serial)) then session.selectedSerial = tonumber(serial) end
    publishUnderground()
  end

  function M.undergroundList(price)
    if not load() or inCustody() then return end
    local case = selectedCase()
    if not case or case.phase ~= "ready" or not vehicleCase(case.inventoryId) or case.seizure then return end
    price = roundPrice(price)
    local now = gameTime()
    case.phase = "listed"
    case.listing = {price = price, listedAt = now, offers = {}, nextOfferAt = now + math.random(10, 25)}
    session.lastResult = nil
    save()
    publishUnderground()
  end

  function M.undergroundUnlist()
    if not load() or inCustody() then return end
    local case = sellableCase()
    if not case then return end
    case.phase, case.listing, session.negotiation = "ready", nil, nil
    save()
    publishUnderground()
  end

  function M.undergroundSetPrice(price)
    if not load() or inCustody() then return end
    local case = sellableCase()
    if not case then return end
    case.listing.price = roundPrice(price)
    scheduleNextOffer(case.listing, undergroundValue(case), gameTime())
    save()
    publishUnderground()
  end

  function M.undergroundAccept(offerId)
    if not load() or inCustody() then return end
    local case = sellableCase()
    local offer = findOffer(case, tonumber(offerId))
    if not offer or offer.expiresAt <= gameTime() then return end
    session.negotiation = nil
    completeUndergroundSale(case, offer.value, false, offer.undercover)
    publishUnderground()
  end

  function M.undergroundDecline(offerId)
    if not load() or inCustody() then return end
    local case = sellableCase()
    if not case then return end
    removeOffer(case, tonumber(offerId))
    save()
    publishUnderground()
  end

  function M.undergroundDismissResult()
    session.lastResult = nil
    if session.negotiation and session.negotiation.result then session.negotiation = nil end
    publishUnderground()
  end

  -- The app's countdowns (identity change, next offer, offer expiry) run on the play-time clock, which
  -- follows real time, so refresh the open app on real time too: a paused simulation must not freeze them.
  local appTick = 0
  local function tickApp(dtReal)
    appTick = appTick - dtReal
    if session.appOpen and appTick <= 0 then
      appTick = 1
      publishUnderground()
    end
  end

  ctx.publishUnderground = publishUnderground
  ctx.sellableCase = sellableCase
  ctx.tickApp = tickApp

  return function()
    buyerArchetypes = ctx.buyerArchetypes
    caseLimit = ctx.caseLimit
    completeUndergroundSale = ctx.completeUndergroundSale
    expensesFor = ctx.expensesFor
    findCase = ctx.findCase
    findOffer = ctx.findOffer
    gameTime = ctx.gameTime
    handoverBlocked = ctx.handoverBlocked
    heatStatus = ctx.heatStatus
    inCustody = ctx.inCustody
    inventory = ctx.inventory
    load = ctx.load
    paintStingChance = ctx.paintStingChance
    perk = ctx.perk
    removeOffer = ctx.removeOffer
    repainted = ctx.repainted
    roundPrice = ctx.roundPrice
    save = ctx.save
    scheduleNextOffer = ctx.scheduleNextOffer
    skillProgress = ctx.skillProgress
    undergroundValue = ctx.undergroundValue
    vehicleCase = ctx.vehicleCase
  end
end
