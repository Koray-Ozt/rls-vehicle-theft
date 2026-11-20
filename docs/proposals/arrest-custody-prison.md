# Arrest, Custody and Prison System (Proposal)

> Status: all three phases are implemented in `lua/ge/extensions/rlsVehicleTheft/custody.lua` and `Custody.vue`.

## Goal

Extend the existing RLS Vehicle Theft arrest consequences into a coherent custody flow without breaking RLS Career Overhaul's native police, fine, time and garage systems.

## Proposed gameplay

1. When RLS confirms an arrest related to vehicle theft, close active theft interactions and prevent duplicate arrest processing.
2. Resolve a police-station destination for the active map. Prefer a verified station location; provide a safe fallback if the map has none.
3. Transfer the player to custody using an appropriate transition. Do not assume the player remains in the seized vehicle.
4. Present a legal representation choice: free public defender or paid private lawyer.
5. Calculate a configurable sentence from confirmed theft offenses and applicable history, with lawyer choice affecting the outcome. Show the result before serving time.
6. Advance in-game time through an RLS-compatible time/sleep integration, using a short configurable real-time duration rather than making the player wait literal game days.
7. Seize all vehicles still marked stolen in the player's active theft cases, including stored vehicles, and reconcile garage slots, listings, workshop tasks, timers and pending offers. Preserve legitimate owned vehicles.
8. Release the player at a verified station exit or a safe map spawn and restore normal gameplay.

## Integration and safety requirements

- Inspect the existing arrest, undercover-sting, vehicle seizure, garage persistence and RLS time APIs before implementation.
- Reuse RLS's arrest/fine handling where possible; never double-charge existing fines.
- Make seizure and sentencing idempotent and safe across save/load, map reloads and interrupted transitions.
- Do not hardcode station coordinates without validating the current map.
- Provide fallback behavior when a station or RLS time-advance API is unavailable.
- Keep sentence parameters and lawyer pricing configurable.
- Avoid teleporting the player into an invalid location or leaving them attached to an impounded vehicle.

## Suggested implementation phases

### Phase 1: Custody foundation
- Hook confirmed arrests
- Station location resolver with safe fallback
- Transition to custody and release spawn
- Regression tests for normal RLS arrests and undercover stings

### Phase 2: Sentencing
- Public defender / private lawyer choice
- Offense-based sentence and fine summary
- Short sentence timer and RLS time advancement

### Phase 3: Seizure and persistence
- Confiscate all active stolen vehicles
- Cancel associated listings, offers and workshop operations
- Save/load recovery and duplicate-event protection

## Acceptance criteria

- A confirmed theft arrest enters custody exactly once.
- The player never spawns in a seized vehicle or invalid location.
- Legal representation choice visibly changes the calculated outcome.
- Sentence completion advances game time without corrupting career state.
- All and only stolen vehicles covered by active cases are seized, including garage-stored cars.
- Existing RLS arrest penalties are not applied twice.
- The player can resume normal gameplay after release.
- Missing station data and interrupted sessions recover safely.

## Findings in RLS Career Overhaul 2.8.1

- **Arrest event.** `overhaul_integration_services_police.arrestVehicle` fires `onPursuitAction(id, "arrest", pursuit)` and then sets the pursuit to mode -1 (frozen). With `autoRelease` the car is released about five seconds later (`"release"`). `pursuit.mode` 1 is a citation, 2 and above an arrest.
- **Fines already charged.** RLS `career/police/playerDriving.lua` charges its pursuit fine on every arrest of the player's vehicle and records a ticket (mode 1) or an arrest (mode 2+) on the inventory vehicle. Custody leaves that fine alone; the theft fine is charged once, at sentencing.
- **Time advance.** `overhaul_world_sleep.sleep(timeOfDay)` only sets a time of day and points the map to the closest garage afterwards, so custody does not use it. Dynamic weather's `overhaul_world_weather.sleepTo(engineTime)` moves forward to the next occurrence of a time of day, advancing the forecast and the day count (`getCalendarState()` gives `dayIndex` and `minuteOfDay`). There is no multi-day call. Without dynamic weather (or while an external override holds the clock) only `scenetree.tod.time` can move.
- **Police stations.** RLS has no police-station API. `rls_west_coast` has a `PoliceStation` building group and a `policeStation_loaner` parking spot in `facilities/delivery/rlsLoaners.sites.json`; no other bundled map has a station on record. Stations are therefore a per-map table in `config.custody.stations` (a fixed position and facing, or a sites-file parking spot), with the nearest garage as fallback. On `rls_west_coast` the player is released in the station's reception hall.
- **Stolen-vehicle state.** `state.cases` of this mod is authoritative; the garage, workshop and Underground code all read it.
- **Moving the player.** RLS fast travel puts the player on foot (`gameplay_walk.setWalkingMode(true)`) and moves the walker with `spawn.safeTeleport`. Custody does the same.

## Phase 1 as implemented

- Trigger: an arrest that makes this mod seize a stolen car (a patrol identified it, or the undercover sting caught the seller). The RLS pursuit mode is not used: a stolen-car pursuit starts at the case's wanted level, usually 1, so a mode filter would skip most theft arrests. Arrests of a fully disguised car stay ordinary RLS arrests.
- `state.custody` is saved as soon as the arrest is confirmed; a second arrest while it is set is ignored. If the game closes or the level changes mid-transfer, the per-second update finishes it once the player is back in the world.
- Transfer: the custody screen (`Custody.vue`, route `rls-theft-custody`) fades to black with BUSTED. The player is put on foot (never in the seized or frozen car) and moved to the station or the nearest garage. If the route cannot open, the game fade screen with a BUSTED title is used instead. If moving fails, the player stays where they were arrested. The take/store key does nothing during custody.
- The player's own car used during a sting stays at the arrest site; RLS releases it and it can be retrieved through RLS as usual.
- Console check: `rlsVehicleTheft.debugCustody()` runs custody for a $20,000 street car and returns the release point and the sentence.

## Phase 2 as implemented

- Stages: `state.custody.stage` moves from `transfer` to `sentencing` to `serving` and is saved at each step. Any stage resumes on the next load: the player is moved to the station again and the flow continues where it stopped. A Phase 1 save without a stage starts at `transfer`.
- One screen: Lua is the state machine and sends each view (`busted`, `sentencing`, `serving`, `leaving`) to `Custody.vue` with the `RlsTheftCustody` event. The screen also asks for the current view when it opens (`getCustodyView`). Answers carry the view's token (`custodyChoose(token, id)`), so a stale click does nothing. If something closes the screen during sentencing, it opens again. Escape does not leave it.
- Theft fine: an arrest that leads to custody calls `seize(reason, case, true)`, which marks the case `fineDeferred` and charges nothing, including on a seizure RLS holds back until later. The fine is set at sentencing. A seizure without custody (handover raid, title transfer, custody off, a second arrest during custody) charges the fine at once, as before.
- Sentence (`config.custody.sentence`): base game hours for what was stolen (street 6, dealership 10, test drive 12, taxi at least 18), +25% per earlier arrest within 3 hours of play (at most 4), +10% per police evade in that car (at most 3), +4 h for a sting, at most 72 h. Arrests are kept in `state.record` (`arrests`, `recent`).
- Lawyers (`config.custody.lawyers`): the public defender is free and leaves the sentence and fine as they are. A private lawyer halves the sentence and cuts the fine by 30%. The fee is 15% of the fine plus $75 per sentence hour, rounded to $50, at least $1,500, and is offered only if the player has the money. Without a screen, the public defender takes the case.
- Choosing pays the fine and fee, moves the mod's play clock (heat, workshop jobs, offers, bans) by the play time the sentence's game hours take at RLS's day length, and enters `serving`, all in one save. The RLS world clock is then moved once (`timeAdvanced` is saved first): through dynamic weather's `sleepTo` in steps of up to 12 hours, so multi-day sentences advance the day count; otherwise only the time of day. `serveSeconds` (5) of real time pass on the black screen, then the player is released with a message stating the time served and what was paid.
- If the custody job fails, the screen is closed, the public defender's fine is charged if nothing was paid yet, and the player is released.

## Phase 3: seizure and persistence

### Rule: what the police take

An arrest that leads to custody is followed by a search of everything the theft reports point to. One rule decides every case in `state.cases`: **a case the police can still link to a theft report is seized; a fully disguised one (new plate and new paint, `disguised(case)`) is not.** This is the rule patrols already use, so laundering a car keeps paying off and the outcome is predictable for the player.

| Case phase | Linked (not disguised) | Disguised |
| --- | --- | --- |
| `transit` (car being carried) | seized, the car is deleted | n/a (a transit car has no new identity) |
| `stored`, `ready` | seized from the garage | kept |
| `workshop` (identity change running) | seized; the identity fee is lost, not refunded | n/a |
| `chopping` (crew stripping it) | seized; no chop payment | kept, the job runs on |
| `listed` | seized; the listing and its offers go with the case | kept, listing and offers stay |

Vehicles that are not in a theft case (bought, rewarded, the player's own car used during a sting) are never touched: `vehicleCase` only matches inventory records tagged with the case serial.

### Charges, fine and sentence

- Every seized car is a count. Its theft fine (`fineFor`) is added to the sentencing fine, so the lawyer's fine factor applies to the total.
- Sentence: the arrested car's hours as in Phase 2, plus `extraCarFactor` (0.5) times the base hours of each other seized car, still at most `maxHours`.
- Open dealership investigations (`state.citations`, test-drive thefts not yet billed) are closed by the court: their amounts join the sentencing fine and they are removed from the list. Without this they would fall due during the sentence (the play clock moves) and arrive as separate fines on the black screen.
- The sentencing screen lists each count: car name, what it was (street, dealership, test drive, taxi) and its fine, then the investigations, then the options as in Phase 2.

### Everything tied to a seized case

- Listing and offers live on the case (`case.listing.offers`) and disappear with it. An open negotiation (`session.negotiation`) on a seized case is closed.
- The undercover operation (`state.sting`) ends if its case is seized.
- A pending no-slot strip dialog (`session.scrapDialog`), a running ignition bypass and a street-car attempt (`session.attempted`, with its forced stop released) are cancelled when custody starts, whatever case they belong to.
- The Underground app is refreshed (`publishUnderground`), and its actions (`undergroundList`, `undergroundAccept`, `undergroundNegotiate` and the rest) and the garage computer rows do nothing while `state.custody` is set.
- A seizure RLS holds back (`removeVehicle` refused, e.g. a logistics job) keeps `case.seizure` with `fineDeferred`, so it completes later without a second fine. Its count is already in the sentence.
- Garage slots are freed by RLS when `removeVehicle` succeeds; nothing else to reconcile.

### Persistence: count first, seize second

`beginCustody` writes the whole search into the saved record before anything is removed:

```lua
state.custody = {
  stage = "transfer", reason, at, level, priors,
  counts = {                -- one per seized case, written before the seizure
    {serial = 12, source = "street", taxi = nil, sting = nil, evades = 1, name = "Gavril D-Series", fine = 6800, arrested = true},
    {serial = 9, source = "inspection", name = "ETK 800", fine = 12600},
  },
  investigations = 5500,    -- closed citations, already removed from state.citations
  sentence = {hours = ..., fine = ...},
}
```

1. Build the count list from the arrested case and every other linked case, close the citations, compute the sentence, save.
2. Seize each counted case still in `state.cases` with `seize(reason, case, true)`.
3. On resume at stage `transfer`, step 2 runs again: cases already seized are gone from `state.cases`, so each car is seized once and each fine is counted once. A crash between the save and the seizures loses nothing.

Phase 2 records with `offense` instead of `counts` are read as a single count.

### Not leading to custody

- Underground handover raid (`market.lua`): the handover is done from the phone and the player is not at the scene, so it stays a seizure with the fine charged at once.
- Title-transfer check (`rlsHooks.lua`): a paperwork check at a sale, also not an arrest. Fine at once, as now.

Neither adds to `state.record`: priors count arrests only, so the sentence formula stays easy to explain.

### Station spots for other maps

`rlsVehicleTheft.debugPosition()` prints the walker's position and facing in the `config.custody.stations` format (`pos = {...}, dir = {...}`), so a station can be added for each RLS Career Collection map by standing in its lobby. Maps without one keep the nearest-garage fallback.

### Tests

Stub tests (45, with Phases 1 and 2):

- linked and disguised cars across all five phases: only the linked ones are seized; a legitimate car is untouched;
- the fine is the sum of the counts and investigations; the sentence adds `extraCarFactor` per extra car and respects `maxHours`;
- crash after the count save: the resume seizes the rest, no fine counted twice;
- a pending seizure completes later without a fine;
- the listing, offers, negotiation, sting and scrap dialog of a seized case are gone; a disguised car's listing stays;
- Underground actions are refused while in custody.

In game: arrest with a second, stored undisguised car and a third, disguised and listed car; check the garage, the Underground app and the sentencing counts.

## Open technical questions

- Station spots for the RLS Career Collection maps (they fall back to the nearest garage until `debugPosition` spots are added).
- Do RLS systems that run per game day (loans, rent, business income) react to days skipped by `sleepTo`? To be checked in game with a multi-day sentence.
