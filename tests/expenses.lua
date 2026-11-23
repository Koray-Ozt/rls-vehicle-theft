-- Run from the repository root: lua tests/expenses.lua
package.path = "lua/ge/extensions/?.lua;" .. package.path

local config = dofile("lua/ge/extensions/rlsVehicleTheft/config.lua")
local current = {serial = 1, inventoryId = 1, expenses = {tracking = 1}}
local old = {serial = 2, inventoryId = 2, identity = "GX000001", expenses = {identity = 2466, paint = 565}}
local rows = {}
local inventory = {getVehicles = function() return {
  [1] = {rlsTheftCase = 1}, [2] = {rlsTheftCase = 2},
} end}
local ctx = {config = config, session = {state = {cases = {current, old}}},
  inventory = function() return inventory end, load = function() return true end,
  gameTime = function() return 0 end, notify = function() end, save = function() end}

overhaul_career_economy_playerAttributes = {
  getAttributeLog = function() return rows end,
  addAttributes = function(change, reason, _, onRecorded)
    local tags = {}
    for _, tag in ipairs(reason.tags or {}) do tags[tag] = true end
    reason.tags = tags -- RLS changes the array before the receipt callback.
    local row = {attributeChange = change,
      reason = {category = reason.category, label = reason.label, tags = tags},
      finance = reason.finance}
    rows[#rows + 1] = row
    if onRecorded then onRecorded(row) end
  end,
}
overhaul_career_economy_payment = {pay = function(price, reason)
  if price.money.amount == 9999 then return false end
  overhaul_career_economy_playerAttributes.addAttributes({money = -price.money.amount}, reason)
  return true
end}

dofile("lua/ge/extensions/rlsVehicleTheft/cases.lua")(ctx)()
dofile("lua/ge/extensions/rlsVehicleTheft/rlsHooks.lua")(ctx)()
ctx.bindRls()

local function debit(amount, tags, category, vehicleId)
  overhaul_career_economy_playerAttributes.addAttributes({money = -amount},
    {category = category or "purchase", finance = {vehicleId = vehicleId or 1}, tags = tags})
end

assert(overhaul_career_economy_payment.pay({money = {amount = 565}},
  {category = "purchase", finance = {vehicleId = 1}, tags = {"vehiclePainting", "buying"}}))
assert(not overhaul_career_economy_payment.pay({money = {amount = 9999}},
  {category = "purchase", finance = {vehicleId = 1}, tags = {"vehiclePainting"}}))
debit(1200, {"partsBought", "buying"})
debit(200, {"tuning", "buying"})
debit(300, {}, "repair")
overhaul_career_economy_payment.pay({money = {amount = -300}},
  {category = "refund", label = "Vehicle repair refund: id 1", finance = {vehicleId = 1}})
debit(100, {"buying"}) -- Unrelated purchases never count.
debit(90, {"partsBought"}, "purchase", 999) -- Another vehicle never counts.
local total, partial, identity, paint, parts, tuning, repair = ctx.expensesFor(current)
assert(total == 1965 and not partial and identity == 0 and paint == 565)
assert(parts == 1200 and tuning == 200 and repair == 0)

-- Existing cases recover only receipts that RLS saved with this exact inventory id.
local function historical(amount, tags, category, label)
  rows[#rows + 1] = {attributeChange = {money = amount},
    finance = {vehicleId = 2}, reason = {tags = tags, category = category, label = label}}
end
historical(-565, {vehiclePainting = true}, "purchase")
historical(-567, {vehiclePainting = true}, "purchase")
historical(-300, {partsBought = true}, "purchase")
historical(-200, {}, "repair")
historical(200, {}, "refund", "Vehicle repair refund: id 2")
local oldTotal, oldPartial, oldIdentity, oldPaint, oldParts = ctx.expensesFor(old)
assert(oldTotal == 3898 and oldPartial and oldIdentity == 2466 and oldPaint == 1132 and oldParts == 300)
assert(select(1, ctx.expensesFor(old)) == oldTotal) -- Repeated UI reads cannot double count.

print("Vehicle spending receipts and historical backfill passed")
