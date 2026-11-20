-- Negotiating an underground offer (selling side of RLS marketplace/negotiation.lua and
-- negotiationPolicy.lua), shown with RLS's negotiation screen in the Underground app.

return function(ctx)
  local M = ctx.M
  local session = ctx.session
  -- From the other parts; bound by the function this file returns once every part is installed.
  local buyerArchetypes, completeUndergroundSale, findCase, findOffer, gameTime, handoverBlocked, inCustody, load, money,
    notify, publishUnderground, removeOffer, roundPrice, save, sellableCase, undergroundValue

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
    if not load() or inCustody() then return end
    local case = sellableCase()
    local offer = findOffer(case, tonumber(offerId))
    if not offer or offer.expiresAt <= gameTime() then return end
    local base = undergroundValue(case)
    local archetype = buyerArchetypes[offer.archetype] or buyerArchetypes.fixer
    local asking = math.max(case.listing.price, offer.value)
    session.negotiation = {
      serial = case.serial, offerId = offer.id, opponentName = offer.buyer .. " (" .. (archetype.label or "Buyer") .. ")",
      quote = offer.quote, archetype = archetype, patience = 1, token = (session.negotiation and session.negotiation.token or 0) + 1,
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
    n.result = outcome and {kind = outcome, price = price,
      expenses = outcome == "sold" and session.lastResult and session.lastResult.expenses or nil,
      partial = outcome == "sold" and session.lastResult and session.lastResult.partial or nil} or {kind = "failed"}
  end

  function M.undergroundCounter(price)
    local n = session.negotiation
    if inCustody() then return end
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
      if session.negotiation ~= n or n.token ~= token then return end
      n.status = "typing"
      publishUnderground()
      job.sleep(thinking)
      if session.negotiation ~= n or n.token ~= token then return end
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
    local n = session.negotiation
    if inCustody() then return end
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
    if not session.negotiation then return end
    session.negotiation = nil
    publishUnderground()
  end


  return function()
    buyerArchetypes = ctx.buyerArchetypes
    completeUndergroundSale = ctx.completeUndergroundSale
    findCase = ctx.findCase
    findOffer = ctx.findOffer
    gameTime = ctx.gameTime
    handoverBlocked = ctx.handoverBlocked
    inCustody = ctx.inCustody
    load = ctx.load
    money = ctx.money
    notify = ctx.notify
    publishUnderground = ctx.publishUnderground
    removeOffer = ctx.removeOffer
    roundPrice = ctx.roundPrice
    save = ctx.save
    sellableCase = ctx.sellableCase
    undergroundValue = ctx.undergroundValue
  end
end
