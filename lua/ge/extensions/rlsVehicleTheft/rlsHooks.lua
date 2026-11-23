-- Wraps RLS functions: title transfers of stolen cars, camera fines, vehicle expenses, test-drive bans
-- and the Vehicle Theft entry on the Skills page.

return function(ctx)
  local session = ctx.session
  local expenseKind = require("rlsVehicleTheft/expenseKind")
  -- From the other parts; bound by the function this file returns once every part is installed.
  local caseForVehicle, decorateSkillsPage, gameTime, inventory, load, notify, seize, vehicleCase

  -- Wrapped RLS functions, so they can be put back when the extension unloads.
  local bindings = {}
  local function rejectTransfer(id)
    if not load() then return nil end
    local case = vehicleCase(id)
    if not case then return nil end
    local reason = case.identity and "Registration check failed during title transfer."
      or "The title transfer flagged the vehicle as stolen."
    seize(reason, case)
    return false
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
    -- Paint uses payment.pay, but parts and tuning debit playerAttributes directly. Capture the actual wallet
    -- receipt at their shared entry point, before RLS turns reason.tags from an array into a lookup table.
    bind(overhaul_career_economy_playerAttributes, "addAttributes", function(original)
      return function(change, reason, fullprice, onRecorded)
        local finance = type(reason) == "table" and reason.finance
        local vehicleId = type(finance) == "table" and finance.vehicleId
        local money = type(change) == "table" and tonumber(change.money)
        local kind = expenseKind(reason, money)
        if not vehicleId or not kind then return original(change, reason, fullprice, onRecorded) end
        return original(change, reason, fullprice, function(row)
          local posted = row and row.attributeChange and tonumber(row.attributeChange.money)
          if posted and ((money < 0 and posted < 0) or (money > 0 and posted > 0)) then
            local case = load() and vehicleCase(vehicleId)
            if case then
              case.expenses = case.expenses or {}
              case.expenses[kind] = math.max(0, (tonumber(case.expenses[kind]) or 0) - posted)
            end
          end
          if onRecorded then onRecorded(row) end
        end)
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
        if seller and load() and (session.state.bans[seller] or 0) > gameTime() then
          notify("This dealership has suspended your test-drive privileges.")
          return false
        end
        return original(...)
      end
    end)
  end

  -- Puts every wrapped RLS function back (extension unloaded).
  local function unbindRls()
    for key, entry in pairs(bindings) do
      if entry.owner[key] == entry.wrapper then entry.owner[key] = entry.original end
    end
  end

  ctx.bindRls = bindRls
  ctx.inspectedDealer = inspectedDealer
  ctx.unbindRls = unbindRls

  return function()
    caseForVehicle = ctx.caseForVehicle
    decorateSkillsPage = ctx.decorateSkillsPage
    gameTime = ctx.gameTime
    inventory = ctx.inventory
    load = ctx.load
    notify = ctx.notify
    seize = ctx.seize
    vehicleCase = ctx.vehicleCase
  end
end
