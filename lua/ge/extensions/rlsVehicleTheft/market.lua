-- Underground market: buyers, offers on a listed car, and the handover that completes a sale.

return function(ctx)
  local session = ctx.session
  local config = ctx.config
  local maxOffers, offerIntervalBase, offerTtlRange, undercoverChances =
    config.maxOffers, config.offerIntervalBase, config.offerTtlRange, config.undercoverChances
  -- From the other parts; bound by the function this file returns once every part is installed.
  local caseVehicleId, count, currentValue, exitVehicle, expensesFor, grantXp, heatStatus, inventory, money,
    notify, notifyPhone, openInvestigation, paintStingChance, perk, removeCase, repainted, save, seize,
    springSting, vehicleCase

  -- Underground market ------------------------------------------------------------------------------
  -- After the identity change the vehicle is sold from the "Underground" phone app: list it at an asking
  -- price, buyers send timed offers, and an offer can be taken as is or negotiated. The flow mirrors the
  -- RLS marketplace (career/market/marketplace.lua and marketplace/negotiationPolicy.lua): a higher asking
  -- price slows offers down, buyers have a patience budget, and counters close part of the gap each turn.

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
      session.lastResult = {kind = "raided"}
      return "raided"
    end
    exitVehicle(inventory().getVehicleIdFromInventoryId(case.inventoryId))
    if inventory().removeVehicle(case.inventoryId) == false then
      notify("The vehicle cannot be handed over right now.")
      return
    end
    local expenses, partial = expensesFor(case)
    openInvestigation(case)
    removeCase(case)
    overhaul_career_economy_payment.reward({money = {amount = price}},
      {label = "Underground vehicle sale", category = "sale", tags = {"vehicleTheft"}}, true)
    save()
    notify("Vehicle handed over. Payment received: " .. money(price))
    count("sold")
    count("revenue", price)
    grantXp(15 + math.min(45, math.floor(price / 400)) + (negotiated and 5 or 0), "Underground vehicle sale")
    session.lastResult = {kind = "sold", price = price, expenses = expenses, partial = partial}
    return "sold"
  end

  -- Called every second from onUpdate: expire offers and bring in new ones.
  local function updateListing(case, now)
    local listing = case.listing
    local changed = false
    for index = #listing.offers, 1, -1 do
      local offer = listing.offers[index]
      if offer.expiresAt <= now and not (session.negotiation and session.negotiation.offerId == offer.id) then
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

  ctx.buyerArchetypes = buyerArchetypes
  ctx.completeUndergroundSale = completeUndergroundSale
  ctx.findOffer = findOffer
  ctx.handoverBlocked = handoverBlocked
  ctx.removeOffer = removeOffer
  ctx.roundPrice = roundPrice
  ctx.scheduleNextOffer = scheduleNextOffer
  ctx.undergroundValue = undergroundValue
  ctx.updateListing = updateListing

  return function()
    caseVehicleId = ctx.caseVehicleId
    count = ctx.count
    currentValue = ctx.currentValue
    exitVehicle = ctx.exitVehicle
    expensesFor = ctx.expensesFor
    grantXp = ctx.grantXp
    heatStatus = ctx.heatStatus
    inventory = ctx.inventory
    money = ctx.money
    notify = ctx.notify
    notifyPhone = ctx.notifyPhone
    openInvestigation = ctx.openInvestigation
    paintStingChance = ctx.paintStingChance
    perk = ctx.perk
    removeCase = ctx.removeCase
    repainted = ctx.repainted
    save = ctx.save
    seize = ctx.seize
    springSting = ctx.springSting
    vehicleCase = ctx.vehicleCase
  end
end
