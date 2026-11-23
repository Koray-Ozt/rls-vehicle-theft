-- Garage computer jobs on a stored car: the identity change and the chop shop, including the
-- no-free-slot strip with its confirmation screen (ui ScrapConfirm.vue).

return function(ctx)
  local M = ctx.M
  local session = ctx.session
  local config = ctx.config
  local chopRates, chopSeconds, scrapRoute, workshopChannel =
    config.chopRates, config.chopSeconds, config.scrapRoute, config.workshopChannel
  -- From the other parts; bound by the function this file returns once every part is installed.
  local carChased, charge, count, currentValue, drivenOutOfGarage, exitVehicle, findCase, gameTime, grantXp, heatStatus, inCustody,
    inventory, load, money, notify, notifyPhone, openInvestigation, ownedGarageNear, perk, removeCase, repainted,
    save, underSting, vehicleCase

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
    -- Recorded per car for the profit estimate in the Underground app; refunded work is taken back out.
    case.expenses = case.expenses or {}
    case.expenses.identity = (tonumber(case.expenses.identity) or 0) + fee
    save()
    notify(string.format("Identity change started. Cost: %s. Ready in %d seconds.", money(fee), seconds))
  end

  -- Chop shop: a stored car can be stripped for parts instead of disguised. It takes less time and no
  -- identity change or repaint, and nothing is handed to a buyer, so there is no raid. It pays less than an
  -- average underground sale after the identity fee (about 31% of the value when cold), and a car with a
  -- fresh report pays less again, so stripping it at once does not dodge the heat.

  local scrapToken = 0

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
    -- Read before the car leaves the inventory. The job runs on its own while the player may be anywhere,
    -- so the phone tells them the car is gone and what it paid.
    local record = case.inventoryId and inventory().getVehicles()[case.inventoryId]
    local name = record and record.niceName or case.scrapName or "The car"
    if case.inventoryId then
      exitVehicle(inventory().getVehicleIdFromInventoryId(case.inventoryId))
      if inventory().removeVehicle(case.inventoryId) == false then return end
    end
    -- Only a car stripped without a garage slot still carries its theft reward: a stored car had it paid out
    -- when it was stored.
    local reward = case.reward
    case.reward = nil
    openInvestigation(case)
    removeCase(case)
    overhaul_career_economy_payment.reward({money = {amount = price}},
      {label = "Chop shop parts sale", category = "sale", tags = {"vehicleTheft"}}, true)
    if reward then
      count("stolen")
      if reward.clean then count("cleanBypass") end
      if reward.carjacked then count("carjacked") end
    end
    save()
    notify("The car was stripped and sold for parts. Payment received: " .. money(price))
    notifyPhone("Parts sold", string.format("%s was stripped and sold for parts. You received %s.", name, money(price)),
      workshopChannel, "success")
    count("chopped")
    count("revenue", price)
    grantXp(10 + (reward and tonumber(reward.xp) or 0) + math.min(30, math.floor(price / 500)), "Parts sold to a chop shop")
  end

  -- A carried car that has no garage slot to go to is not lost: the crew takes it away and strips it, which
  -- takes as long as the chop shop and pays the same. From then on it is an ordinary "chopping" case that has
  -- no inventory record: the phone app shows its countdown, it survives a reload and it counts toward the case
  -- limit. The car is gone from the world, so police, arrests and title checks (all matched by vehicle) can no
  -- longer touch it. The theft XP and milestones are paid when the crew finishes, like the money.
  -- RLS only prices cars it holds in the inventory, so the car is registered without taking a slot just long
  -- enough to read its value, then removed like a stripped car.
  local function scrapCarried(case)
    session.scrapDialog = nil
    local vehId = session.liveId
    local id = vehId and inventory().addVehicle(vehId, nil, {owned = true, takesNoInventorySpace = true})
    if not id then
      notify("The chop shop could not take the car. Try again.")
      return
    end
    local record = inventory().getVehicles()[id]
    local name = record and record.niceName
    local value = tonumber(overhaul_career_market_valueCalculator.getInventoryVehicleSellValue(id)) or 0
    exitVehicle(vehId)
    if inventory().removeVehicle(id) == false then
      notify("The chop shop could not take the car. Try again.")
      return
    end
    session.liveId, session.lastStoreRefusal, session.parkedTicks = nil, nil, 0
    case.scrapValue, case.scrapName = math.max(0, value), type(name) == "string" and name or nil
    case.value = math.max(case.value or 0, case.scrapValue)
    case.phase, case.readyAt = "chopping", gameTime() + chopSeconds
    save()
    notify(string.format("No garage slot was free. The crew took the car away to strip it: about %s in %d seconds.",
      money(chopValue(case)), chopSeconds))
  end

  local function openScrapDialog(case)
    scrapToken = scrapToken + 1
    session.scrapDialog = {token = scrapToken, serial = case.serial}
    if extensions.ui_router.navigate(scrapRoute) == false then
      session.scrapDialog = nil
      notify("Could not open the confirmation screen.")
    end
  end

  -- What the confirmation screen shows. The price itself is only known once RLS has priced the car, so the
  -- screen states the rate the crew pays at the car's current heat.
  function M.getScrapState()
    local dialog = session.scrapDialog
    local case = dialog and findCase(dialog.serial)
    if not case or case.phase ~= "transit" then return nil end
    local heat = heatStatus(case)
    return {token = dialog.token, seconds = chopSeconds, heatLabel = heat.label, hot = heat.stage == "hot",
      rate = math.floor(chopRates[heat.stage] * perk("fenceValue", 1) * 100 + 0.5)}
  end

  -- action: "accept", "decline", or "leave" (the screen closed). The car is checked again on accept, since the
  -- screen can stay open while the situation changes.
  function M.scrapInput(token, action)
    local dialog = session.scrapDialog
    if not dialog or dialog.token ~= token then return end
    session.scrapDialog = nil
    if action == "leave" then return end
    extensions.ui_router.navigate("play")
    if action ~= "accept" then return end
    local case = findCase(dialog.serial)
    local vehicle = session.liveId and getObjectByID(session.liveId)
    if not case or case.phase ~= "transit" or not vehicle then return end
    if carChased(session.liveId) then
      notify("Lose the police before selling the car for parts.")
    elseif not ownedGarageNear(vehicle) then
      notify("Drive into a garage you own.")
    elseif vehicle:getVelocity():length() > 1 then
      notify("Stop the vehicle before selling it for parts.")
    elseif inventory().hasFreeSlot() then
      notify("A garage slot is free now: store the car normally.")
    else
      scrapCarried(case)
    end
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
          if session.state and findCase(case.serial) == case and vehicleCase(case.inventoryId) then
            startIdentity(case)
            overhaul_career_career.closeAllMenus()
          end
        end}
      row.rlsTheftChop = {id = "rlsTheftChop", order = 81,
        label = string.format("Strip for parts (~%s, %d s)", money(chopValue(case)), chopSeconds),
        callback = function()
          if session.state and findCase(case.serial) == case and vehicleCase(case.inventoryId) then
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
    if not load() or inCustody() then return end
    for _, case in ipairs(session.state.cases) do addComputerRow(case, buttons) end
  end

  -- Every second while the crew strips the car.
  local function updateChop(case, now)
    -- Driving the car out of the garage interrupts the crew: no payment, the car is yours again.
    if drivenOutOfGarage(case) then
      case.phase, case.readyAt = "stored", nil
      save()
      notify("You drove the car out before the crew finished. Nothing was paid.")
    elseif now >= case.readyAt then
      finishChop(case)
    end
  end

  -- Every second while the identity change runs. Returns true when the work stopped because the car left.
  local function updateIdentity(case, now)
    if drivenOutOfGarage(case) then
      -- Same rule as the chop shop: the work stops when the car leaves. The workshop returns the fee.
      local refund = tonumber(case.identityFee) or 0
      case.phase, case.readyAt, case.identityFee = "stored", nil, nil
      if case.expenses and case.expenses.identity then
        case.expenses.identity = math.max(0, case.expenses.identity - refund)
      end
      if refund > 0 then
        overhaul_career_economy_payment.reward({money = {amount = refund}},
          {label = "Vehicle identity change refund", category = "service", tags = {"vehicleTheft"}}, true)
      end
      save()
      notify("You drove the car out before the new identity was finished. The workshop refunded " .. money(refund) .. ".")
      return true
    elseif now >= case.readyAt then
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
      local name = record and record.niceName or "The car"
      if repainted(case) == false then
        notify("Identity change complete. The paint still matches the theft report: repaint it at the garage computer before selling it in the Underground phone app.")
        notifyPhone("New identity ready", name .. " has its new plate. Repaint it before you list it.",
          workshopChannel, "warning")
      else
        notify("Identity change complete. Sell it from the Underground phone app.")
        notifyPhone("New identity ready", name .. " has its new plate and is ready to list.", workshopChannel, "success")
      end
      save()
    end
    return false
  end

  ctx.openScrapDialog = openScrapDialog
  ctx.updateChop = updateChop
  ctx.updateIdentity = updateIdentity

  return function()
    carChased = ctx.carChased
    charge = ctx.charge
    count = ctx.count
    currentValue = ctx.currentValue
    drivenOutOfGarage = ctx.drivenOutOfGarage
    exitVehicle = ctx.exitVehicle
    findCase = ctx.findCase
    gameTime = ctx.gameTime
    grantXp = ctx.grantXp
    heatStatus = ctx.heatStatus
    inCustody = ctx.inCustody
    inventory = ctx.inventory
    load = ctx.load
    money = ctx.money
    notify = ctx.notify
    notifyPhone = ctx.notifyPhone
    openInvestigation = ctx.openInvestigation
    ownedGarageNear = ctx.ownedGarageNear
    perk = ctx.perk
    removeCase = ctx.removeCase
    repainted = ctx.repainted
    save = ctx.save
    underSting = ctx.underSting
    vehicleCase = ctx.vehicleCase
  end
end
