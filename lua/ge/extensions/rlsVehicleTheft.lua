-- RLS Vehicle Theft: the extension BeamNG loads (scripts/rls_vehicle_theft/modScript.lua).
-- This file only puts the parts together and runs the per-frame and per-second updates. Each part lives in
-- lua/ge/extensions/rlsVehicleTheft/ and is installed with the same ctx, the way RLS builds its taxi
-- service (overhaul/integration/services/taxi/core.lua):
--   ctx.M        this extension's table: parts add the hooks and the functions the UI calls to it
--   ctx.config   the gameplay tunables (config.lua)
--   ctx.session  state several parts share; session.state is the saved career data of the current profile
--   ctx.<name>   the functions each part offers the others
-- A part is a function(ctx) that returns a link function. Once every part is installed, the links run and
-- each part picks up the functions it uses from the others.

local M = {}

local ctx = {
  M = M,
  config = require("rlsVehicleTheft/config"),
  session = {parkedTicks = 0},
}

-- In dependency order, though any order works: parts only call each other after linking.
local parts = {
  "core",           -- clock, messages, money, saved career data
  "progression",    -- Vehicle Theft skill, perks, counters, milestones
  "cases",          -- open theft cases, heat, seizure
  "rlsHooks",       -- wrapped RLS functions
  "streetCars",     -- which street cars can be taken and how
  "traffic",        -- replacing cars taken from traffic
  "ignition",       -- ignition bypass and engine start
  "theft",          -- the take/store key and opening a case
  "garage",         -- storing the car in an owned garage
  "workshop",       -- identity change and chop shop
  "police",         -- reports, patrols, undercover stings
  "market",         -- underground buyers, offers and sales
  "negotiation",    -- negotiating an offer
  "undergroundApp", -- the Underground phone app
}

local links = {}
for _, name in ipairs(parts) do
  table.insert(links, require("rlsVehicleTheft/" .. name)(ctx))
end
for _, link in ipairs(links) do link() end

local session = ctx.session

-- Runs once a second for every open case. The first step that settles the case for this tick ends it.
local function updateCase(case, now)
  if ctx.settleLostCase(case) then return end
  if case.phase == "chopping" then
    ctx.updateChop(case, now)
    return
  end
  if ctx.checkAbandon(case) then return end
  if case.phase == "workshop" then
    if ctx.updateIdentity(case, now) then return end
  elseif case.phase == "listed" and case.listing then
    ctx.updateListing(case, now)
  end
  if case.phase == "transit" and ctx.updateStorage(case) then return end
  ctx.updatePatrol(case, now)
end

function M.onUpdate(dtReal, dt)
  if not ctx.load() then
    ctx.dropIgnition()
    return
  end
  session.state.clock = session.state.clock + (tonumber(dtReal) or 0)
  ctx.tickIgnition(dtReal)
  if session.attempted then ctx.updateAttempt(dt) end
  ctx.tickApp(dtReal)
  session.patrolCheck = session.patrolCheck - dt
  if session.patrolCheck > 0 then return end
  session.patrolCheck = 1
  ctx.bindRls()
  local now = ctx.gameTime()
  ctx.updateCitations(now)
  for index = #session.state.cases, 1, -1 do
    if session.state.cases[index] then updateCase(session.state.cases[index], now) end
  end
  ctx.updateSting(now)
  ctx.updateTrafficTopUp(now)
end

function M.onOverhaulSaveCurrentProfile(path)
  if session.state then
    overhaul_career_saveSystem.jsonWriteFileSafe(path .. ctx.config.saveFile, session.state, true)
  end
end

function M.onOverhaulBeforeSetProfile()
  session.profile, session.state, session.attempted, session.liveId = nil, nil, nil, nil
  session.negotiation, session.lastResult = nil, nil
  session.parkedTicks, session.scrapDialog = 0, nil
  ctx.resetIgnition(true)
  ctx.resetForcedStops()
  ctx.resetTrafficTopUp()
end

function M.onClientEndMission()
  session.attempted, session.liveId = nil, nil
  session.parkedTicks, session.scrapDialog = 0, nil
  ctx.resetIgnition(false)
  ctx.resetForcedStops()
  ctx.resetTrafficTopUp()
  -- Vehicle ids do not survive a level change: an ongoing undercover chase starts over on the next drive.
  if session.state and session.state.sting then session.state.sting.pursuing = nil end
end

function M.onExtensionUnloaded()
  ctx.unbindRls()
end

return M
