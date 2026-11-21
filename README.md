# RLS Vehicle Theft

Steal a vehicle, get it into your garage, change its identity, and find a buyer through the **Underground** phone app. Police attention, vehicle condition, workshop costs and undercover buyers can change the outcome. A theft arrest can now lead to a police search, sentencing and custody.

**Latest release:** [0.10.0](https://github.com/Koray-Ozt/rls-vehicle-theft/releases/tag/v0.10.0) · **Tested with:** BeamNG.drive 0.40.6 and RLS Career Overhaul 2.8.1 · **License:** [MIT](LICENSE)

[Download](https://github.com/Koray-Ozt/rls-vehicle-theft/releases/latest) · [Install](#installation) · [Quick start](#quick-start) · [Gameplay](#playing) · [Controls](#controls) · [Known limits](#current-limits) · [Release notes](#changes)

This is an unofficial add-on for RLS Career Overhaul. It is not affiliated with RLS Modding or BeamNG GmbH.

## Features

| Feature | What you can do |
|---|---|
| **Steal** | Take parked cars, moving civilian vehicles, idle taxis and dealership cars. Bypass the ignition when the engine is off. |
| **Manage** | Store up to four active theft cases as you level up. Change a car's identity, repaint it, or strip it for parts. |
| **Sell** | List cars in Underground, compare timed offers and estimated net profit, and negotiate with different buyers. |
| **Survive** | Deal with heat, patrols, undercover stings, police searches of stolen cars and court sentencing after a theft arrest. |
| **Progress** | Earn Vehicle Theft XP, unlock perks and claim six theft milestones. |

## Dependencies

This mod is an add-on for RLS Career Overhaul. It does **not** include RLS and does nothing without it.

| Dependency | Version | Required | Notes |
|---|---|---|---|
| [BeamNG.drive](https://www.beamng.com/game/) | 0.40.6 | Yes | The version the mod was last played on (0.9.5 and earlier: 0.40.5). |
| [RLS Career Overhaul](https://github.com/RLS-Modding/rls_career_overhaul) | 2.8.1 | Yes | Install and enable it separately. 0.9.5 and earlier were played on 2.8.0 Hotfix. Other RLS versions are untested. |
| An RLS career profile | — | Yes | Theft works in an active RLS career with an owned garage. A free slot is needed to store a car; a full garage can still strip a car for parts. |

At runtime the mod calls RLS's career, garage, police, parking, marketplace, payment, skills and milestone systems. The Underground phone app also loads two files from inside RLS: the negotiation screen (`components/negotiation/NegotiationChatWindow.vue`) and the phone screen helper (`composables/usePhoneScreen.js`). An RLS update that renames or moves these may break the mod until it is updated.

The mod has no other dependencies and does not modify installed RLS or BeamNG game files. Custom control bindings are saved by BeamNG in the user's settings. The mod ships one patched copy of an RLS UI file (see below) that BeamNG's virtual file system loads in place of the original.

## Installation

1. Install and enable **RLS Career Overhaul 2.8.1**.
2. [Download `rls_vehicle_theft_0.10.0.zip`](https://github.com/Koray-Ozt/rls-vehicle-theft/releases/download/v0.10.0/rls_vehicle_theft_0.10.0.zip). Do not unpack it.
3. Put the ZIP in your BeamNG user folder under `mods` (for example `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods`).
4. Remove any earlier `rls_vehicle_theft_*.zip` from that folder, enable the mod in the Mod Manager, and restart the game.
5. Open an RLS career and install **Underground** from the phone's App Store to sell stolen cars.

To build the ZIP yourself, compress the folders `gameplay`, `lua`, `scripts`, `settings` and `ui` so they sit at the root of the archive.

## Quick start

1. On foot, press **Ctrl + Shift + J** beside a parked car, a slow civilian vehicle or an idle taxi. You can also take a dealership car during inspection or a test drive.
2. Bypass the ignition if the engine is off. Lose any police pursuit, then park inside a garage you own to store the car.
3. At the garage computer, **Change vehicle identity** and repaint the car. You can instead **Strip for parts** without preparing it for sale.
4. In **Underground**, set an asking price, list the car and accept or negotiate a buyer's offer. Check the estimated net profit before taking a deal.

### Where to go

| What | Where |
|---|---|
| **Underground** phone app (required for selling) | Phone → **App Store** → **Underground** (Vehicles category). Install it once per career. |
| Change the stolen car's identity | Garage computer → select the car → **Change vehicle identity** |
| Repaint it | Garage computer → RLS's painting option |
| Sell it for parts instead | Garage computer → select the car → **Strip for parts** |
| List, take offers, negotiate, sell | **Underground** phone app |
| Vehicle Theft skill level and perks | RLS **Skills** page or the phone's **Skills** app → **Vehicle Theft**, or the top of the **Underground** app |
| Theft milestones | RLS **Milestones** page (General filter) |

## Controls

| Input | Context | Action |
|---|---|---|
| **Ctrl + Shift + J** (default) | On foot beside a parked car, slow civilian car or idle taxi | Start taking it; stay close until the attempt completes. |
| **Ctrl + Shift + J** (default) | Inspecting or test-driving a dealership car | Take the car. |
| **Ctrl + Shift + J** (default) | Stopped in a garage you own | Store the stolen car, or confirm stripping it if no slot is free. Getting out inside the garage also stores it. |
| **Space** or **Enter** | Ignition Bypass | Begin or lock a signal. Mouse buttons on the screen also work. |
| **Cancel** | Ignition Bypass | Leave the attempt. Canceling after Begin counts as a failure and starts the 8-second cooldown. |
| Phone **Back** | Underground | Leave a negotiation; press again to close the app. |

Change the take/store shortcut in **Underground → Settings → Change binding** or BeamNG's Controls menu under **RLS Vehicle Theft: Take or store vehicle**. Keyboard keys, controller buttons and mouse buttons other than left-click are supported; right-click and axes are reserved.

## Playing

### Take a vehicle

- **Parked car:** Stand by its door, press the take/store shortcut and stay close for 4 seconds (3 seconds with the level 5 perk). A clean theft is reported after 90–180 seconds; missed ignition signals and nearby traffic witnesses shorten that delay.
- **Moving civilian car:** On foot, get within about 6 m while it is below about 30 km/h and press the shortcut. The driver stops; stay beside the car for 2.5 seconds. Walk away before the attempt finishes and the car drives off.
- **Taxi:** An available or off-duty taxi can be taken the same way. A taxi coming for you, waiting for you or carrying you is excluded. You immediately receive $60–$240 from the driver's cash float, and its theft starts a level 3 pursuit.
- **Dealership car:** Use the shortcut while inspecting a car or driving it on a test drive. A test-drive theft also triggers an investigation and suspends test drives at that dealership.

### Start and store it

A stopped traffic car already has its engine running. If the engine is off, open **Ignition Bypass**, select **Begin**, and lock three signals within 25 seconds. Press **Space** or click **Lock signal** while the white marker is in the green zone. A miss costs 4 seconds; failure or cancellation after Begin starts an 8-second cooldown, and alarm-triggering misses persist on that car. Vehicle Theft perks widen the target and reduce the miss penalty. Release the parking brake if the engine starts but the car will not move.

Lose any pursuit and stop inside a garage you own. The car stores after a few seconds standing still, when you get out, or when you press the shortcut. It uses one normal garage slot; a car left at the entrance does not count as inside. Theft XP and milestones are awarded when storage succeeds. If every slot is full, pressing the shortcut while stopped inside the garage offers to have the crew strip the car instead. Underground shows that job's countdown, and the theft rewards arrive when stripping finishes.

### Prepare and sell it

At the garage computer, select **Change vehicle identity** to give the car a new plate. The job takes 150 seconds and costs 23% of the car's value, at least $1,200; perks reduce both. The Underground app shows the countdown. Driving the car out before completion cancels the job and refunds the fee. Repaint it at the same computer to break the police report's colour match.

In **Underground**, set an asking price and choose **List for sale** once the identity job is done. Up to four buyer offers can wait at once; each expires after a few minutes. Accept, decline or negotiate an offer from anywhere. A handover completes only while the car is parked and not in a police pursuit. The app shows the asking price, offers and sale result as estimated profit, loss or break-even after recorded identity and repaint costs. It marks old cases with incomplete expense history as **partial costs**; police fines are excluded from that estimate.

### Alternatives and multiple cases

- **Ditch an unstored car:** Walk about 120 m away with no police pursuit. You get no payout or XP and no theft fine. A stolen test-drive car still leads to its dealership investigation.
- **Strip a stored car:** Choose **Strip for parts** at the garage computer. The job takes 90 seconds, needs no repaint and has no handover raid risk. It pays 20% of vehicle value while Hot, 23% while Warm or 26% while Cold, before Vehicle Theft perks. Driving it out of the garage cancels the job.
- **Handle several cars:** You can hold two open cases, three at Vehicle Theft level 10 or four at level 25. Only one newly stolen car can be in transit at a time. Select a stored case at the top of the Underground app; garage actions are per car. Each extra open case increases attention from police and buyers.

### Asking price and negotiation

The app shows the vehicle's heat state, the time until it cools, and why its value is reduced. A fresh report is **Hot** for 2 minutes at 54% of normal sell value, then **Warm** for 4 minutes at 58%, and then **Cold** at 61% (Vehicle Theft perks raise each rate by up to 15%). Heat also decides how close a patrol has to get to spot the car (see Consequences). A patrol sighting that starts a pursuit or recognizes the original paint refreshes both timers. Changing the plate caps heat at Warm while the original paint remains, until a patrol recognizes that paint: then the car is Hot again. Changing the plate and repainting it breaks the match and makes it Cold. Buyers explain hot and warm offers in their messages. Listing below the shown underground value brings offers sooner and closer to your price; listing well above it makes buyers rarer and keeps their offers near the underground value. This follows the RLS marketplace.

Negotiation uses the RLS negotiation screen. Each counter-offer costs the buyer patience, more so the further your price is from the underground value. A buyer moves part of the way toward your price, never past their budget, and walks away when their patience runs out, which removes the offer. Buyer types differ: chop shops pay least and lose patience fastest, exporters pay most and stay longest.

### Undercover buyers

Some buyers are undercover police: 2% of offers for a Cold car, 3% for a Warm one and 4% for a Hot one. They look like any other buyer. The only tells are an offer that is a little too good and a buyer who stays unusually patient in a negotiation. Accepting their offer, directly or after negotiating, is a sting instead of a sale:

- The deal is off and nothing is paid. The car stays yours, but the police now know its new plate and the colour the buyer saw. It is a freshly reported car again: to sell it you need another identity change (a new plate series) and another repaint.
- If you are driving when the sting springs, unmarked units start a pursuit at once. If you are on foot, the chase starts the next time you drive any vehicle within 10 minutes.
- Lose them and the operation ends (+15 XP, counts for Ghost Driver). Get arrested and you go into custody ([Arrest and custody](#arrest-and-custody)): the stung car is seized, the sentence gets 4 extra hours, and RLS charges its own arrest fine as usual.
- Until then no workshop or chop shop touches the car, and the Underground app shows the operation's state.

## Vehicle Theft skill and milestones

**Vehicle Theft** is an RLS career skill with 50 levels on the same XP curve as RLS's other skills. It appears on RLS's Skills page and in the phone's Skills app, and the **Underground** app shows your level and XP at the top. RLS adds its usual level milestones for it.

| Action | XP |
|---|---|
| Take a car from its driver | 12 |
| Take a parked car (bypass with a miss / without a miss) | 15 / 20 |
| Take a dealership car (inspection / test drive) | 15 / 20 |
| Store it in your garage | 10, plus the XP for taking it (paid only once the car is stored) |
| Lose the police in a stolen car (first three times per car) | 10 |
| Escape an undercover sting | 15 |
| Finish the identity change | 5 |
| Strip a car for parts | 10 + 1 per $500 of the price (at most +30) |
| Underground sale | 15 + 1 per $400 of the price (at most +45), +5 when negotiated above the opening offer |

A full theft usually earns 60–100 XP: level 5 takes roughly 15–20 thefts and level 10 roughly 60.

| Level | Perk |
|---|---|
| 3 / 10 / 25 | Ignition bypass target zone 10% / 20% / 30% wider |
| 5 | Getting into a parked car takes 3 seconds instead of 4 |
| 8 / 18 / 30 / 45 / 50 | Underground buyers value your cars 3% / 6% / 10% / 12% / 15% higher |
| 10 | A missed ignition signal costs 3 seconds instead of 4 |
| 10 / 25 | You can handle 3 / 4 stolen cars at once instead of 2 |
| 12 / 25 / 40 | Identity changes cost 10% / 20% / 30% less |
| 15 | A parked car taken cleanly is noticed 25% later |
| 20 / 40 | Identity changes take 120 / 90 seconds instead of 150 |
| 30 | Underground offers arrive 15% sooner |
| 35 / 50 | Unrepainted car: patrol recognition 22% / 15% instead of 30%, handover raid 15% / 10% instead of 20% |

Theft milestones appear with RLS's general milestones and pay money when claimed: **Car Thief** (vehicles stolen), **Carjacker** (cars taken from their drivers), **Clean Hands** (ignitions bypassed without a miss), **Ghost Driver** (police lost in a stolen car), **Fence** (underground sales) and **Underground Earnings** (total underground income). Rewards follow RLS's own milestone payouts: $100 per tier for the first four and $250 per tier for the two selling milestones. A theft counts for Car Thief, Carjacker and Clean Hands once the car is stored. Counting started with 0.7.0; earlier thefts are not included.

## Consequences

- **Taking a traffic vehicle from its driver** is reported at once, and the nearest police unit starts a pursuit right away, even if it has not seen you yet.
- **Taking a taxi** pays the driver's cash at once, $60–$240 in steps of $5, and you keep it whatever becomes of the car. A taxi is a commercial vehicle: the pursuit starts at RLS wanted level 3 (every unit, roadblocks) instead of 1, and so does every later pursuit of that car, whether a patrol spots it or recognizes its paint.
- **Taking a parked vehicle** goes unnoticed for 90–180 seconds if you match every signal cleanly. Each missed signal trips the alarm and shortens that time. Two or more nearby traffic vehicles act as witnesses and shorten it further.
- Once a vehicle is reported, a patrol that spots it starts an RLS pursuit and refreshes its hot period. How close the patrol has to be depends on heat: about 160 m while Hot, 100 m while Warm and 60 m once Cold. After you evade a pursuit, patrols ignore the vehicle for 45 seconds.
- A new identity hides the plate, not the paint. If the vehicle still has the colour it had when you stored it, each new patrol that sees you driving it (within the same heat-based range) has a 30% chance to recognize it and start a pursuit, half that once the report is Cold. The underground handover has a 20% chance to be raided, which seizes the vehicle and charges the theft fine. The Underground app marks such a vehicle as risky and shows the current raid chance.
- **Holding several cars raises the heat.** Each case you already have open makes the next report come in about 35% sooner, and raises the chance that a patrol recognizes an unrepainted car or that a handover is raided by 15% per extra case.
- **Camera fines** (speed and red-light cameras) are not charged to you while you drive the stolen car with its original plate; they go to the registered owner. Once the identity change is done, the car is yours and RLS charges them normally.
- A car with a new plate **and** a new colour is no longer matched to the theft report. An ordinary police arrest for another offence charges the usual RLS fine but does not seize it, and the search after a theft arrest leaves it alone.
- An official marketplace listing can be published normally. If you try to complete the title transfer, the sale is canceled, the listing is removed, the vehicle is seized, and a fine is charged. The sale pays out nothing.
- Stealing a vehicle from a company-affiliated dealer reduces that company's RLS reputation by 120 points during an inspection or 220 points during a test drive.
- Test-drive theft suspends test-drive privileges at that dealership. A later investigation issues a fine after the car is sold, stripped or left behind.
- A stolen car that leaves your inventory some other way (not through the Underground app, the chop shop or a seizure) is still on record: the theft fine is charged and you are told why.
- All timers (reports, heat, workshop jobs, offers, test-drive bans and investigations) run on play time. They keep running while the game is paused or the phone is open, but stop while the game is closed.

### Arrest and custody

An arrest that confirms a theft (a patrol identified the stolen car, or undercover units caught the seller of a sting) takes you into custody. RLS still charges its own arrest fine first.

- **BUSTED.** The screen goes black, you are put on foot and taken to the police station: the Belasco station's reception hall on West Coast, the nearest garage on maps without a station on record.
- **The search.** The police seize the arrested car and every other open case they can still link to a theft report, including cars stored in your garages, in the workshop, being stripped or listed in the Underground app; their listings and offers go with them. A car with a new plate **and** a new colour is not linked and stays yours. Cars you bought or own legally are never touched. Open test-drive investigations are closed into the same sentence.
- **Sentencing.** Each seized car is a count with its theft fine. The sentence is in game hours: 6 for a street car, 10 for a dealership car, 12 for a test drive, at least 18 for a taxi, +25% for each arrest in the last 3 hours of play (up to four), +10% for each time that car got away from the police (up to three), +4 hours for a sting, and half the base hours of every other seized car, at most 72 hours.
- **Your lawyer.** The public defender is free and leaves the sentence and fines as they are. A private lawyer halves the sentence and cuts the fines by 30%; the fee (15% of the fines plus $75 per hour of the sentence, at least $1,500) is paid up front and needs the money in hand.
- **Serving.** A few seconds of black screen, while the game clock moves forward by the sentence (over several days if needed) and the mod's own timers with it: heat cools, workshop jobs finish, offers expire. Then you are released at the station.
- Closing the game during custody is safe: it continues where it stopped the next time you load the profile, and nothing is seized or charged twice.
- The take/store key, the Underground app's actions and the garage computer's theft rows do nothing during custody.

## Project structure

Everything is packaged in the mod ZIP. BeamNG's virtual file system merges its files with RLS, so the mod does not edit installed game or RLS files.

| Area | Purpose |
|---|---|
| `lua/ge/extensions/rlsVehicleTheft.lua` and `lua/ge/extensions/rlsVehicleTheft/` | Career state, theft, police, custody, workshops, offers and progression. `config.lua` holds gameplay values; `propConfigs.lua` maps simplified parked cars to real variants. |
| `ui/ui-vue/mods/rls_vehicle_theft/` | Underground, Ignition Bypass, full-garage strip confirmation and Custody screens. |
| `gameplay/overhaul/` | RLS registration for the phone app, Vehicle Theft skill and UI routes. |
| `lua/ge/extensions/core/input/actions/rls_vehicle_theft.json` and `settings/inputmaps/` | The take/store action and default binding. |
| `scripts/rls_vehicle_theft/modScript.lua` | Loads the BeamNG extension. |

The mod wraps selected RLS functions for stolen-car title transfers, garage and marketplace actions, and skill data, then restores them when the extension unloads. Its bundled copy of RLS's `usePhoneSkillsData.js` adds Vehicle Theft to the phone Skills list; that RLS-owned file retains its AGPL-3.0 header.

## Current limits

- **Parked vehicle variants:** RLS parks simplified props with no engine or drivetrain. The mod replaces a taken prop with a real car, preserving its paint and plate and matching its visible variant by hand. Unknown prop variants fall back to the model's default configuration. The Robot Van has no matching base-game model and cannot be taken.
- **Traffic density:** Available cars depend on BeamNG's traffic setting. The mod replaces taken traffic cars but does not raise that setting; on a quiet road it shows a one-time hint.
- **One car in transit:** You can hold 2–4 open cases, but must store, strip or ditch the newly stolen car before taking another. An unstored car does not survive a reload and can result in a theft fine. Existing saved cases are migrated automatically.
- **RLS UI compatibility:** The mod reuses RLS's negotiation component and phone helper, and includes a patched copy of its phone Skills data file. An RLS update to those files may require a mod update.

### In-game validation

Version 0.10.0 has been played in BeamNG 0.40.6 with RLS 2.8.1: theft, ignition bypass, garage storage, identity changes, Underground sales, the Vehicle Theft skill and perks, and theft milestones. Custody was played on West Coast, including a patrol arrest, seizure of other stolen cars, the private lawyer, resuming after closing the game and a multi-day sentence. RLS's daily economy systems behaved as expected during the time skip. The mod ships no automated regression tests.

## Troubleshooting

- **Underground is missing:** Check that RLS Career Overhaul and this mod are enabled, open an RLS career, then install Underground from the phone's App Store.
- **A car will not store:** Stop fully inside a garage you own and lose the police first. Storage needs a free slot; if the garage is full, press the take/store shortcut there to choose stripping instead. For a failed attempt, look for `rlsVehicleTheft` lines in `beamng.log`.
- **Few ordinary traffic cars appear:** Raise **Options → Gameplay → Traffic**. The mod cannot spawn more cars than your traffic setting allows.
- **After an update:** Keep only one `rls_vehicle_theft_*.zip` in the mods folder and restart the game.

When reporting a problem, include the BeamNG, RLS and mod versions, the steps to reproduce it, and relevant `rlsVehicleTheft` lines from `beamng.log`.

## License

This mod is released under the [MIT License](LICENSE). The license covers this mod's own files only. RLS Career Overhaul and BeamNG.drive are separate works under their own licenses and are not included.

## Changes

### 0.10.0

This release adds arrest and custody: a theft arrest now takes you to the police station, the police search for your other stolen cars, a court sets a sentence and a lawyer can lower it, and the game clock moves forward while you serve it. Saves from 0.9.6 load without any action.

**Added**
- **Custody after a theft arrest.** When a patrol identifies a stolen car or undercover units catch the seller of a sting, the screen goes black with BUSTED, you are put on foot and taken to the police station: the Belasco station's reception hall on West Coast, the nearest garage on maps without a station on record. RLS still charges its own arrest fine. An arrest of a fully disguised car stays an ordinary RLS arrest.
- **The police search.** The arrested car and every other open case the police can still link to a theft report are seized, wherever the car is: carried, stored, in the workshop, being stripped or listed in the Underground app. Its listing and offers go with it. A car with a new plate and a new colour is not linked and stays yours, listing included. Cars you own legally are never touched. Open test-drive investigations are closed into the same sentence.
- **Sentencing and your lawyer.** A sentencing screen lists each seized car with its theft fine. The sentence is in game hours: 6 for a street car, 10 for a dealership car, 12 for a test drive, at least 18 for a taxi, more for recent arrests, police evades and a sting, plus half the base of every other seized car, at most 72 hours.
  - The public defender is free and leaves the sentence and fines as they are.
  - A private lawyer halves the sentence and cuts the fines by 30%. The fee (15% of the fines plus $75 per hour, at least $1,500) is paid up front and needs the money in hand.
- **Serving the sentence.** A few seconds of black screen, while the game clock moves forward by the sentence, over several days if needed (through RLS's dynamic weather; without it only the time of day moves). The mod's own timers move with it: heat cools, workshop jobs finish, offers expire. Then you are released with a message stating the time served and what you paid.
- Console helpers: `rlsVehicleTheft.debugCustody()` runs custody for an imaginary car without searching your real ones, and `rlsVehicleTheft.debugPosition()` prints where you stand as a station entry for `config.lua`.

**Changed**
- The theft fine of an arrest is charged at sentencing instead of with the seizure, so the lawyer can lower it, and it is charged once. Seizures without an arrest (a handover raid, a failed title transfer) charge it at once, as before.
- During custody the take/store key, the Underground app's actions and the garage computer's theft rows do nothing.
- Custody is saved at every step. Closing the game during it is safe: it continues where it stopped the next time you load the profile, and no car is seized or fine charged twice.

**Tested**
- Version 0.10.0 was played on West Coast with BeamNG 0.40.6 and RLS 2.8.1. In-game checks covered the BUSTED screen, station transfer, seizure of other stolen cars, sentencing, the private lawyer, release, resuming after the game was closed, and a multi-day sentence. RLS's daily economy systems (loans, rent and business income) behaved as expected during the time skip. The theft-to-sale flow, Vehicle Theft skill and perks, and theft milestones were also checked in-game with RLS 2.8.1. The mod does not ship automated regression tests.

**Upgrading from 0.9.6**
- Remove `rls_vehicle_theft_0.9.6.zip` (or any older version) from your `mods` folder before adding 0.10.0. Saves load without any action.

### Older releases

[Read the full release history](CHANGELOG.md).
