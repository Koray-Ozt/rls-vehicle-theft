-- Gameplay tunables of RLS Vehicle Theft, in one place. Every module reads them from ctx.config; nothing
-- here changes at run time. Values a single module uses only for its own bookkeeping stay in that module.

return {
  -- The mod's career data, saved next to the RLS profile.
  saveFile = "/career/rlsVehicleTheft.json",

  -- Theft fines (share of the car's value, at least the minimum) and the company reputation a dealership
  -- theft costs.
  rules = {
    street = {fine = 0.34, minimum = 3000},
    inspection = {fine = 0.42, minimum = 4500, reputation = 120},
    testDrive = {fine = 0.50, minimum = 5500, reputation = 220},
  },

  -- Taking a taxi: the driver's cash float (a shift's change and small fares, in steps of $5) comes with the
  -- car and is paid at once. A taxi is a commercial vehicle, so its pursuits start at RLS's top wanted level.
  taxiTheft = {cashMin = 60, cashMax = 240, wantedLevel = 3},

  -- Ignition bypass: stages to match, per-stage marker speed (track units/s on a 15-unit track) and
  -- target half-width. Each value tier sets its own time limit.
  ignitionStages = 3,
  ignitionSpeeds = {6, 7.5, 9},
  ignitionHalfWidths = {2.1, 1.9, 1.7},
  -- The street value is the vehicle config's catalog Value; dealership theft uses the listing value.
  -- Unknown values use the standard tier. Perks still apply after the tier's width adjustment.
  ignitionValueTiers = {
    {maxValue = 15000, label = "Basic security", seconds = 29, width = 1.15, speed = 0.9},
    {maxValue = 60000, label = "Standard security", seconds = 25, width = 1, speed = 1},
    {label = "Advanced security", seconds = 23, width = 0.85, speed = 1.1},
  },
  -- The UI shows the marker slightly behind the simulation (30 Hz updates + UI bridge latency),
  -- so a lock also counts if the marker was in the zone within this many seconds before the click.
  ignitionGrace = 0.16,
  ignitionMissPenalty = 4,
  ignitionFailCooldown = 8,
  -- How long a car may be out of reach (RLS shuffling parked cars) before the attempt fails.
  ignitionLostGrace = 1.5,
  ignitionRoute = "rls-theft-ignition",
  scrapRoute = "rls-theft-scrap",

  -- Carjacking a moving car: the fastest car that can be flagged down (m/s, about 29 km/h) and how close
  -- the player has to be to it while it is moving (metres).
  carjackMaxSpeed = 8,
  carjackReach = 6,

  -- Heat: how long a fresh report stays Hot and then Warm.
  heatHotSeconds = 120,
  heatWarmSeconds = 240,
  -- Share of the car's value the underground pays at each heat stage (before the fenceValue perk).
  heatMultipliers = {hot = 0.54, warm = 0.58, cold = 0.61},
  -- How close a patrol has to be to spot a reported car at each heat stage, in metres.
  sightRanges = {hot = 160, warm = 100, cold = 60},
  -- Share of underground buyers who are undercover police, by the car's heat when the offer comes in.
  undercoverChances = {hot = 0.04, warm = 0.03, cold = 0.02},
  -- How long an undercover operation keeps looking for a seller who has not been chased yet (play time).
  stingSeconds = 600,

  -- Custody after an arrest that confirms a theft (custody.lua): the black custody screen (route, Custody.vue)
  -- fades in over fadeSeconds and shows BUSTED for at least holdSeconds while the player is booked, then the
  -- sentencing choice, then serveSeconds of real time while the sentence passes. The player is released on foot
  -- at the map's police station. A station is either a position (pos, and dir to face) or a parking spot in a
  -- sites file of the map (sitesFile, spot); a map without one releases the player at the nearest garage.
  custody = {
    enabled = true,
    fadeSeconds = 0.5,
    holdSeconds = 2,
    serveSeconds = 5,
    route = "rls-theft-custody",
    -- Sentence in game hours: the base for what was stolen (a taxi at least taxiHours), raised by priorFactor
    -- for each earlier arrest within priorWindowSeconds of play time (at most maxPriors) and by evadeFactor
    -- for each time the car got away from the police (at most maxEvades); a sting adds stingHours. Each other
    -- stolen car the search finds adds extraCarFactor of its own base hours.
    sentence = {
      baseHours = {street = 6, inspection = 10, testDrive = 12},
      taxiHours = 18,
      stingHours = 4,
      priorFactor = 0.25,
      maxPriors = 4,
      priorWindowSeconds = 10800,
      evadeFactor = 0.10,
      maxEvades = 3,
      extraCarFactor = 0.5,
      maxHours = 72,
    },
    -- What each lawyer does to the sentence (hours) and the theft fine (fine). A private lawyer charges a share
    -- of the fine plus an hourly rate on the sentence, rounded to $50, at least feeMinimum, paid up front.
    lawyers = {
      public = {label = "Public defender", note = "Free. The court hands down the full sentence and fine.",
        hours = 1, fine = 1},
      private = {label = "Private lawyer", note = "Paid up front. Halves the sentence and cuts the fine by 30%.",
        hours = 0.5, fine = 0.7, feeShare = 0.15, feePerHour = 75, feeMinimum = 1500},
    },
    -- Real minutes per game day when RLS does not report its day length: a sentence moves the mod's own
    -- timers (heat, workshop jobs, offers, bans) by the play time that many game hours take.
    fallbackDayMinutes = 60,
    stations = {
      -- The reception hall inside the Belasco police station, facing the counter.
      rls_west_coast = {
        label = "the Belasco police station",
        pos = {-743.46, 744.92, 86.24},
        dir = {-0.997, -0.028, 0},
      },
    },
  },

  -- Walk this far from a stolen car you have not stored, with no pursuit on you, and it is left behind.
  abandonDistance = 120,

  -- Chop shop: how long stripping takes, and the share of the car's value it pays at each heat stage.
  chopSeconds = 90,
  chopRates = {hot = 0.20, warm = 0.23, cold = 0.26},

  -- Underground market: up to maxOffers waiting offers, one every offerIntervalBase seconds at a fair asking
  -- price, each open for offerTtlRange seconds.
  maxOffers = 4,
  offerIntervalBase = 45,
  offerTtlRange = {150, 300},

  -- The Underground phone app (gameplay/overhaul/phone/apps/rls-underground.json) and its notification
  -- channels. Finished chop shop and identity jobs have their own channel, so the player can mute them
  -- apart from buyer offers.
  undergroundAppId = "rls-underground",
  undergroundEvent = "RlsTheftUnderground",
  offerChannel = "rlsUnderground.newOffer",
  workshopChannel = "rlsUnderground.workshop",

  -- Vehicle Theft skill (gameplay/overhaul/domains/careerSkills/skills/vehicleTheft/info.json). Perks are
  -- step functions of the level ({level, value} tiers) and match the unlock cards in that file.
  skillKey = "careerSkills-vehicleTheft",
  skillFile = "/gameplay/overhaul/domains/careerSkills/skills/vehicleTheft/info.json",
  perkTiers = {
    ignitionWidth = {{3, 1.10}, {10, 1.20}, {25, 1.30}},
    missPenalty = {{10, 3}},
    parkedWait = {{5, 3}},
    fenceValue = {{8, 1.03}, {18, 1.06}, {30, 1.10}, {45, 1.12}, {50, 1.15}},
    identityFee = {{12, 0.9}, {25, 0.8}, {40, 0.7}},
    quietEntry = {{15, 1.25}},
    identityTime = {{20, 120}, {40, 90}},
    offerPace = {{30, 0.85}},
    paintRecognition = {{35, 0.22}, {50, 0.15}},
    paintSting = {{35, 0.15}, {50, 0.10}},
    caseLimit = {{10, 3}, {25, 4}},
  },
}
