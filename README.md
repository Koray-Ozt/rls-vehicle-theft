# RLS Vehicle Theft

Version 0.9.4 keeps stolen cars from being lost when your garages are full, fixes parked cars failing mid-theft, and builds on 0.9.0's undercover police buyers and heat-aware street police in the vehicle theft feature for RLS Career Overhaul. Take a vehicle from the street or a dealership, store it in an owned garage, change its identity, and sell it to underground buyers from the **Underground** phone app. Police, vehicle damage, workshop costs, and fines can turn a sale into a loss.

This is an unofficial add-on. It is not affiliated with RLS Modding or BeamNG GmbH.

## Dependencies

This mod is an add-on for RLS Career Overhaul. It does **not** include RLS and does nothing without it.

| Dependency | Version | Required | Notes |
|---|---|---|---|
| [BeamNG.drive](https://www.beamng.com/game/) | 0.40.5 | Yes | The version the mod was built and played on. |
| [RLS Career Overhaul](https://github.com/RLS-Modding/rls_career_overhaul) | 2.8.0 Hotfix | Yes | Install and enable it separately. Other RLS versions are untested. |
| An RLS career profile | — | Yes | Theft only works in an active RLS career, with at least one owned garage that has a free slot. |

At runtime the mod calls RLS's career, garage, police, parking, marketplace, payment, skills and milestone systems. The Underground phone app also loads two files from inside RLS: the negotiation screen (`components/negotiation/NegotiationChatWindow.vue`) and the phone screen helper (`composables/usePhoneScreen.js`). An RLS update that renames or moves these may break the mod until it is updated.

The mod has no other dependencies and does not modify installed RLS or BeamNG game files. Custom control bindings are saved by BeamNG in the user's settings. The mod ships one patched copy of an RLS UI file (see below) that BeamNG's virtual file system loads in place of the original.

## Installation

1. Install and enable **RLS Career Overhaul 2.8.0 Hotfix**.
2. Download `rls_vehicle_theft_<version>.zip` from this repository's [Releases](../../releases) page. Do not unpack it.
3. Put the ZIP in your BeamNG user folder under `mods` (for example `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods`).
4. Remove any earlier `rls_vehicle_theft_*.zip` from that folder, enable the mod in the Mod Manager, and restart the game.
5. In your RLS career, install **Underground** from the phone's App Store.

To build the ZIP yourself, compress the folders `gameplay`, `lua`, `scripts`, `settings` and `ui` so they sit at the root of the archive.

## Quick reference

### Controls

| Key | When | What it does |
|---|---|---|
| **Default: Ctrl + Shift + J** | On foot, at the door of a parked civilian car | Start taking it. Stay beside the car for 4 seconds. |
| **Default: Ctrl + Shift + J** | On foot, next to a civilian car driving below about 30 km/h | Flag it down. The driver stops; stay next to the car for 2.5 seconds. |
| **Default: Ctrl + Shift + J** | Inspecting a dealership car, or driving it on a test drive | Take that car. |
| **Default: Ctrl + Shift + J** | Driving the stolen car, parked inside a garage you own | Store it. Getting out inside the garage stores it too. |
| **Space** or **Enter** | Ignition Bypass screen | **Begin**, then **Lock signal** when the white marker is in the green zone. The buttons work with the mouse as well. |
| **Cancel** button | Ignition Bypass screen | Give up the attempt. After **Begin** this counts like a failed attempt: wait 8 seconds, and the misses stay on that car. |
| Phone **Back** | Underground app | Leave a negotiation; press again to close the app. |

Change the shortcut in **Underground phone app → Settings → Change binding**. Keyboard keys, mouse buttons other than left-click, and controller buttons are supported; right-click and axes are reserved. You can also change it in BeamNG's Controls settings under **RLS Vehicle Theft: Take or store vehicle**.

### What to install and where to go

| What | Where |
|---|---|
| **Underground** phone app (required for selling) | Phone → **App Store** → **Underground** (Vehicles category). Install it once per career. |
| Change the stolen car's identity | Garage computer → select the car → **Change vehicle identity** |
| Repaint it | Garage computer → RLS's painting option |
| Sell it for parts instead | Garage computer → select the car → **Strip for parts** |
| List, take offers, negotiate, sell | **Underground** phone app |
| Vehicle Theft skill level and perks | RLS **Skills** page or the phone's **Skills** app → **Vehicle Theft**, or the top of the **Underground** app |
| Theft milestones | RLS **Milestones** page (General filter) |

### At a glance

1. Take a car with the configured shortcut (default **Ctrl + Shift + J**) and start it (ignition bypass if the engine is off).
2. Lose the police, then stop inside a garage you own. The theft XP is paid when the car is stored.
3. At the garage computer: **Change vehicle identity**, and repaint it.
4. In the **Underground** app: set a price, **List for sale**, then accept or negotiate an offer.

## Playing

1. **Take a vehicle.** In RLS Career, walk up to the door of a parked or stopped civilian vehicle, press your configured shortcut (default **Ctrl + Shift + J**) and stay beside it for 4 seconds. You can also carjack a civilian car that is still driving below about 30 km/h: step next to it (within about 6 m) and press the shortcut. The driver brakes to a stop; stay next to the car for 2.5 seconds and it is yours. Walk away first and the car drives off again. The same shortcut works while inspecting a dealership vehicle or driving it during a dealership test drive.
2. **Start the engine.** A stopped traffic vehicle already has its engine running, so you take it without the bypass. If the engine is off, select **Begin** on the **Ignition Bypass** screen. Press **Lock signal** (or **Space**) when the white marker is in the green zone. Match all three signals within 25 seconds. A miss costs 4 seconds; if the time runs out, wait 8 seconds before trying again. Canceling a started attempt (or closing the screen) counts the same way: the 8-second wait applies and the alarm your misses tripped stays tripped on the next try at that car. Vehicle Theft perks widen the target zone and shorten the miss penalty. If the engine starts but the parking brake is on, release it before driving.
3. **Store it.** Lose any active pursuit and stop the vehicle inside a garage you own. It is stored after a few seconds standing still, when you get out, or when you press your configured shortcut. It uses a normal garage slot. If every slot is taken, press the shortcut while stopped inside the garage and a confirmation screen offers to have the crew take the car away and strip it for parts. It takes the same 90 seconds as the chop shop and is paid like it. The Underground app shows the countdown, the case counts toward your open cases, and the XP and theft milestones are paid when the crew finishes. A vehicle left at the entrance is not stored, because the garage computer only lists vehicles inside the garage. The XP and the theft milestones for taking the car are counted at this point.
4. **Change its identity and repaint it.** At the garage computer, select the vehicle and choose **Change vehicle identity**. This also gives it a new plate. The work costs 23% of the car's value (at least $1,200) and takes 150 seconds; Vehicle Theft perks make it cheaper and faster. The Underground app counts down the remaining time. If you drive the car out of the garage before it is done, the work stops and the fee is refunded. Repaint it with the RLS painting option on the same computer: the theft report describes the colour it had when you stored it.
5. **Sell it from the Underground phone app.** Install **Underground** from the phone's App Store once. When the identity change is done, open the app, set an asking price and choose **List for sale**. Buyers send offers over time; each offer expires after a few minutes, and up to four can wait at once. For each offer choose **Accept**, **Decline** or **Negotiate**. You can sell from anywhere, but buyers only meet a parked car: not while you are driving it and never while the police are chasing it. The vehicle is handed over and the money is paid at once.

**Or ditch it, or chop it.** If you do not want to keep a stolen car, there are two ways out. Walk about 120 m away from a car you have not stored, with no police on you, and you leave it behind: no theft fine, but no payout and no XP, and the car is towed. A test-drive car is the exception: the dealership knows who took it and its investigation still ends in a fine. Once a car is stored, you can skip the identity change and choose **Strip for parts** at the garage computer. It takes 90 seconds, needs no repaint and has no raid risk. The chop shop pays 26% of the car's value when it is Cold, 23% when Warm and 20% when Hot (Vehicle Theft perks raise it by up to 15%). That is less than an average Underground sale after the identity fee, but quick and safe. If you drive the car out of the garage before the crew finishes, the job is cancelled and nothing is paid.

**Several cars at once.** You can hold up to 2 open cases at the same time: each stored car, whether it is waiting, being disguised, stripped or listed, counts as one. Vehicle Theft level 10 raises the limit to 3 and level 25 to 4. You can only carry one freshly stolen car at a time: store it, sell it or ditch it before taking the next. Pick which car the **Underground** app shows with the buttons at its top; the garage computer lists the actions for each stored car separately. More open cases means more heat (see Consequences).

### Asking price and negotiation

The app shows the vehicle's heat state, the time until it cools, and why its value is reduced. A fresh report is **Hot** for 2 minutes at 54% of normal sell value, then **Warm** for 4 minutes at 58%, and then **Cold** at 61% (Vehicle Theft perks raise each rate by up to 15%). Heat also decides how close a patrol has to get to spot the car (see Consequences). A patrol sighting that starts a pursuit or recognizes the original paint refreshes both timers. Changing the plate caps heat at Warm while the original paint remains, until a patrol recognizes that paint: then the car is Hot again. Changing the plate and repainting it breaks the match and makes it Cold. Buyers explain hot and warm offers in their messages. Listing below the shown underground value brings offers sooner and closer to your price; listing well above it makes buyers rarer and keeps their offers near the underground value. This follows the RLS marketplace.

Negotiation uses the RLS negotiation screen. Each counter-offer costs the buyer patience, more so the further your price is from the underground value. A buyer moves part of the way toward your price, never past their budget, and walks away when their patience runs out, which removes the offer. Buyer types differ: chop shops pay least and lose patience fastest, exporters pay most and stay longest.

### Undercover buyers

Some buyers are undercover police: 2% of offers for a Cold car, 3% for a Warm one and 4% for a Hot one. They look like any other buyer. The only tells are an offer that is a little too good and a buyer who stays unusually patient in a negotiation. Accepting their offer, directly or after negotiating, is a sting instead of a sale:

- The deal is off and nothing is paid. The car stays yours, but the police now know its new plate and the colour the buyer saw. It is a freshly reported car again: to sell it you need another identity change (a new plate series) and another repaint.
- If you are driving when the sting springs, unmarked units start a pursuit at once. If you are on foot, the chase starts the next time you drive any vehicle within 10 minutes.
- Lose them and the operation ends (+15 XP, counts for Ghost Driver). Get arrested and the stung car is seized and the theft fine charged, on top of RLS's own arrest fine.
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
- **Taking a parked vehicle** goes unnoticed for 90–180 seconds if you match every signal cleanly. Each missed signal trips the alarm and shortens that time. Two or more nearby traffic vehicles act as witnesses and shorten it further.
- Once a vehicle is reported, a patrol that spots it starts an RLS pursuit and refreshes its hot period. How close the patrol has to be depends on heat: about 160 m while Hot, 100 m while Warm and 60 m once Cold. After you evade a pursuit, patrols ignore the vehicle for 45 seconds.
- A new identity hides the plate, not the paint. If the vehicle still has the colour it had when you stored it, each new patrol that sees you driving it (within the same heat-based range) has a 30% chance to recognize it and start a pursuit, half that once the report is Cold. The underground handover has a 20% chance to be raided, which seizes the vehicle and charges the theft fine. The Underground app marks such a vehicle as risky and shows the current raid chance.
- **Holding several cars raises the heat.** Each case you already have open makes the next report come in about 35% sooner, and raises the chance that a patrol recognizes an unrepainted car or that a handover is raided by 15% per extra case.
- **Camera fines** (speed and red-light cameras) are not charged to you while you drive the stolen car with its original plate; they go to the registered owner. Once the identity change is done, the car is yours and RLS charges them normally.
- A car with a new plate **and** a new colour is no longer matched to the theft report. An ordinary police arrest for another offence charges the usual RLS fine but does not seize it.
- An official marketplace listing can be published normally. If you try to complete the title transfer, the sale is canceled, the listing is removed, the vehicle is seized, and a fine is charged. The sale pays out nothing.
- Stealing a vehicle from a company-affiliated dealer reduces that company's RLS reputation by 120 points during an inspection or 220 points during a test drive.
- Test-drive theft suspends test-drive privileges at that dealership. A later investigation issues a fine after the car is sold, stripped or left behind.
- A stolen car that leaves your inventory some other way (not through the Underground app, the chop shop or a seizure) is still on record: the theft fine is charged and you are told why.
- All timers (reports, heat, workshop jobs, offers, test-drive bans and investigations) run on play time. They keep running while the game is paused or the phone is open, but stop while the game is closed.

## What the mod contains

Everything lives in this mod's ZIP; no RLS file is edited. BeamNG merges all mods into one virtual file system, and RLS discovers phone apps and skills by scanning shared folders, so it reads this mod's files as if they were its own.

| File in the ZIP | Purpose |
|---|---|
| `lua/ge/extensions/rlsVehicleTheft.lua` | All logic: theft, ignition, storage, identity change, police, underground market, XP, perks and milestones |
| `gameplay/overhaul/domains/careerSkills/skills/vehicleTheft/info.json` | The Vehicle Theft skill: 50 levels and their perk cards |
| `gameplay/overhaul/phone/apps/rls-underground.json` | The Underground phone app definition |
| `ui/ui-vue/mods/rls_vehicle_theft/UndergroundApp.vue` | The Underground app screen |
| `ui/ui-vue/mods/rls_vehicle_theft/IgnitionBypass.vue` | The ignition bypass screen |
| `ui/ui-vue/mods/rls_vehicle_theft/ScrapConfirm.vue` | The confirmation screen for stripping a car when no garage slot is free |
| `ui/images/rls_vehicle_theft/underground.png` | The Underground app icon |
| `gameplay/overhaul/ui/routes/rls-theft-routes.json` | The ignition screen's UI route |
| `lua/ge/extensions/core/input/actions/rls_vehicle_theft.json`, `settings/inputmaps/keyboard_rls_vehicle_theft.json` | The take/store action and its default **Ctrl + Shift + J** binding |
| `ui/ui-vue/mods/rls_career_overhaul/overhaul/modules/career/composables/usePhoneSkillsData.js` | A copy of RLS's phone Skills data file (AGPL-3.0, header kept) with Vehicle Theft added to its fixed list of visible skills. Three added lines; an RLS update to this file is overridden by it |
| `scripts/rls_vehicle_theft/modScript.lua` | Loads the extension |

Where the mod changes RLS behaviour (blocking official sales of stolen cars, suspending test drives, adding the skill to the Skills page), it wraps the RLS function while the game runs and restores it when the extension unloads.

## Current limits

Parked cars in RLS are simplified props with no engine or drivetrain. When you take one, the mod replaces it with the real model of the same car, in the same place, paint and plate, using that model's default configuration. The Ardente and Tograc props have no real model in the base game, so they cannot be taken.

The number of cars you can take from traffic depends on BeamNG's own traffic setting (Options > Gameplay > Traffic). With a low setting the road holds only a few ordinary cars, and you will keep seeing the same ones. The mod replaces every car you take with a new one, but it does not change the setting. After a theft on a quiet road it shows a one-time hint about it.

The mod handles 2 to 4 open cases at once (see Vehicle Theft level 10 and 25), but only one freshly stolen car can be carried at a time. Store the stolen vehicle before leaving the session. An unstored vehicle does not survive a reload, and the case can result in a fine when you return. Profiles saved with an earlier version are converted automatically; a case that was open keeps working.

The mod ships no automated tests. Theft, the ignition screen, storage, the identity change and the Underground app have been played in BeamNG 0.40.5 with RLS 2.8.0. The Vehicle Theft skill, its perks, the theft milestones and the identity countdown fix in 0.7.0 have been checked only by reading the code against RLS, not yet in the game. The Underground app reuses RLS's negotiation component and phone screen helper, so a future RLS update that moves those files would break the app's negotiation screen.

## License

This mod is released under the [MIT License](LICENSE). The license covers this mod's own files only. RLS Career Overhaul and BeamNG.drive are separate works under their own licenses and are not included.

## Changes

### Unreleased

**Added**
- **Estimated net profit in the Underground app.** The asking price, each buyer offer and the sold result now show the net after the car's recorded expenses, as profit, loss or break-even (worded, not only colored).
  - Only the identity change fee is tracked per car, and it is taken back out if the workshop refunds it. Repaint costs are not reported to the mod, so a repainted car is labeled "partial costs". Police fines are not counted.

### 0.9.4

This release fixes two problems found in reviews and lets you sell a stolen car for parts when every garage slot is taken. Saves from 0.9.0 load without any action. Versions 0.9.1 to 0.9.3 were never published; their changes are included here.

**Added**
- **Strip for parts when no garage slot is free.** A second stolen car used to be lost when every slot in your garages was taken. Now, with the car stopped inside a garage you own, the shortcut opens a confirmation screen that offers to have a crew strip it for parts.
  - The screen shows what the crew pays (the chop shop rate at the car's current heat), how long it takes (90 seconds) and the theft report status.
  - Choose **Strip for parts** and the crew takes the car away; choose **Keep the car** (or press Esc) and nothing changes.
  - The strip is an ordinary chop shop case: the Underground app shows the car and its countdown, it counts toward your open cases, it survives a reload and it pays like the chop shop. The car is gone from the road, so police, arrests and title checks can no longer touch it.
  - The theft XP, the Car Thief, Clean Hands and Carjacker milestones, and the dealership investigation for a test-drive car are applied when the crew finishes.
  - The car is checked again when you confirm: it must be stopped inside your garage with no police chase, and no slot may have become free in the meantime.
- Taking a parked car now writes the reason to the game log when it cannot be completed (`beamng.log`, lines containing `rlsVehicleTheft`). Include those lines when reporting a problem.

**Fixed**
- Carjacking a moving civilian car could leave you without control of it. The car's AI is now switched off again once you are seated, so the car responds to steering, throttle and brakes.
- A stolen car now leaves with its engine running. Cars taken from traffic or the street were swapped for their real model with the ignition off, and the engine was never started when the ignition bypass was skipped. The starter now runs for every street theft and only cranks when the engine is not already running.
- Taking a parked car could stop with "no longer available" even though the car was still there. The ignition bypass now waits up to 1.5 seconds if RLS briefly deactivates or moves the car, instead of ending at once. If the parking pool cannot be found by name, the car is released from whichever pool holds it.

**Upgrading from 0.9.0**
- Remove `rls_vehicle_theft_0.9.0.zip` (or any older version) from your `mods` folder before adding 0.9.4. Saves load without any action.

### 0.9.0

This release adds undercover police buyers, makes heat matter on the street as well as at the sale, rebalances the chop shop and closes several loopholes and bugs found in a review of the gameplay flow. Saves from 0.8.x load without any action; see **Upgrading** below.

**Added**
- **Undercover buyers.** Some underground buyers are undercover police: 2% of offers for a Cold car, 3% for a Warm one and 4% for a Hot one. They pose as any buyer type and are never marked in the app.
  - Tells: their offer is 5–10% better than usual, and in a negotiation they lose patience at half the normal rate.
  - Accepting their offer, directly or at the end of a negotiation, springs a sting instead of a sale. Nothing is paid and the listing is removed. The car stays yours, but the police now know its new plate and the colour the buyer saw, so it is a freshly reported, Hot car again. Selling it needs another identity change (the plate comes from a new series: GX, then GY, GZ, GW) and another repaint.
  - If you are driving when the sting springs, unmarked units start a pursuit at once. If you are on foot, the chase starts the next time you drive any vehicle within 10 minutes; after that the operation loses track of you.
  - Lose the pursuit: the operation ends, you earn 15 XP and it counts towards Ghost Driver. Get arrested: the stung car is seized and its theft fine is charged, on top of RLS's own arrest fine.
  - While the operation runs, the garage computer refuses both the identity change and Strip for parts for that car, so it cannot be stripped to escape the sting.
  - The Underground app shows the sting result, whether units are looking for you or chasing you, and how long the operation has left.

**Changed: heat and police**
- Heat now affects the police, not only the price. A reported car is spotted by a patrol within about 160 m while Hot, 100 m while Warm and 60 m once Cold. Before, every patrol within 160 m reacted whatever the heat, so a car shown as Cold in the app was exactly as easy to spot.
- A Cold report halves the chance that a patrol recognizes the original paint under a new plate (30% → 15% at the base rate).
- When a patrol recognizes the original paint of a car with a new plate, the car is now Hot again, as the notification already said. Before, the new plate kept it at Warm. Hot offers and the buyers' Hot messages can now actually occur in a sale.
- The heat descriptions in the app explain what each stage means for patrols.

**Changed: economy and progression**
- Strip for parts now pays by heat: 26% of the car's value when Cold, 23% when Warm and 20% when Hot (was a flat 34%). The flat rate paid as much as or more than an average Underground sale after the identity fee, with no risk, and stripping a car straight away skipped the heat system. Vehicle Theft value perks still raise it by up to 15%.
- The XP for taking a car, and the Car Thief, Carjacker and Clean Hands milestones, are now counted when the car is stored in your garage. Taking a car and walking away from it no longer earns XP or milestone money. The XP amounts are unchanged.
- Leaving a test-drive car behind no longer avoids the dealership's investigation: it ends in a fine, as it does after a sale or a chop.

**Changed: selling and workshops**
- Buyers only meet a parked car. An Underground sale is refused while you are driving the car or while police are chasing it, so a sale can no longer make a car vanish in the middle of a pursuit. The app explains why and disables **Accept**. If a buyer agrees to your price in a negotiation while the handover is blocked, the deal waits until you can take it.
- Driving a car out of the garage during the identity change now stops the work and refunds the fee, the same rule as Strip for parts. Both jobs are interrupted only when the car actually leaves the garage, not when you just get in.

**Changed: timers**
- All timers (report delays, heat, workshop and chop jobs, offers, test-drive bans and investigations) now run on play time instead of the computer clock. They keep running while the game is paused or the phone is open, but no longer advance while the game is closed.

**Fixed**
- Taking a car from its driver (a traffic car flagged down while driving) put you in the passenger seat, where the car cannot be driven. BeamNG keeps the traffic driver as a seat occupant after the car leaves traffic, so the driver's seat looked taken. That occupant is now removed and you are seated as the driver. Dealership cars use the same seating.
- Taking cars out of traffic slowly emptied the road: the game never refills traffic, so every stolen traffic car was one fewer for good, until only taxis and police (which cannot be taken) were left. Each stolen traffic car is now replaced by a newly spawned one, chosen from a wider mix of models and preferring models that are not already on the road ([#5](https://github.com/Koray-Ozt/rls-vehicle-theft/issues/5)). If the road is quiet (a low traffic setting in Options > Gameplay > Traffic), a one-time hint suggests raising it. The mod writes what it does to `beamng.log` under the `rlsVehicleTheft.traffic` tag.
- A stolen car was never stored automatically while you sat in it, still, inside the garage if you already had another open case. Another case reset the countdown every second. Getting out or pressing the key still worked.
- Canceling the ignition bypass, or closing its screen, after a miss reset the misses and skipped the 8-second wait, so a miss could be undone for free. A started attempt that is canceled now counts like a failed one: the wait applies and the tripped alarm carries over to the next attempt on that car.
- Closing the ignition bypass screen some other way than **Cancel** left a flagged-down traffic car stopped in the road with its parking brake on.
- When RLS could not assign a garage slot while storing a car, the car was seized and the full theft fine was charged. The car now stays in your inventory and the case stays open.
- A stolen car that left your inventory outside the mod (not through the Underground app, the chop shop or a seizure) was fined without any message. You are now told what happened.
- The Underground app showed a fixed 20% raid chance and fixed 54/58/61% value rates. It now shows the values with your perks and open cases applied, and also warns about the raid risk on a listed car.
- The app's step text for an unstored car said to get out of it; it now says to stop inside the garage, and that the theft XP is paid on storage.

**Upgrading from 0.8.x**
- Remove `rls_vehicle_theft_0.8.1.zip` (or any older version) from your `mods` folder before adding 0.9.0.
- Existing cases, offers and timers continue where they were; the play-time clock starts from the moment you load the save.

### 0.8.1

**Added**
- Three-stage vehicle heat: Hot for 2 minutes at 54% value, Warm for 4 more minutes at 58%, then Cold at 61%. Existing Vehicle Theft value perks apply to every stage.
- Heat status, time to cool, value impact and risk guidance in the Underground app. Buyer messages explain Hot and Warm discounts.
- An Underground app Settings page to rebind the take/store action. Keyboard keys, middle/side mouse buttons and controller buttons can be assigned; Ctrl + Shift + J remains the default. BeamNG stores custom bindings in the user's input settings.
- The Settings page is a gear icon in the Underground header, and the heat explanation (stage, value rates, risk) is a tooltip on the heat badge and its cooldown timer instead of a separate text block.
- A stolen car is stored automatically once it is parked, still, inside a garage you own. Getting out inside the garage stores it too.

**Changed**
- Police report delays remain independent from heat cooldowns. A patrol sighting that starts a pursuit or recognizes the original paint refreshes heat.
- Changing the plate caps heat at Warm while the original paint remains; changing both plate and paint makes the vehicle Cold.
- The take/store action is ignored while the Underground app is open, so its controls cannot trigger it accidentally.

**Fixed**
- The "press Ctrl+Shift+J to store it" notifications named the default key even after it was rebound. They now show your current binding.

### 0.8.0

**Added**
- Several stolen cars at once: 2 open cases, 3 from Vehicle Theft level 10 and 4 from level 25. Each extra case shortens the report time of the next theft and raises recognition and raid chances.
- Ditching a stolen car: walk about 120 m away from an unstored car with no police on you and it is left behind, with no theft fine.
- Strip for parts: a stored car can be sold to a chop shop at the garage computer in 90 seconds for about 34% of its value, without an identity change or repaint and without raid risk. Driving the car away cancels the job. Pays XP and counts towards the underground earnings.
- The Underground app shows your Vehicle Theft level and XP, and a car selector when several cases are open.
- Vehicle Theft is listed in the phone's Skills app, through a patched copy of RLS's `usePhoneSkillsData.js` (three added lines, AGPL header kept).
- Perk cards for the 3rd and 4th car slots.

**Changed**
- Saved data keeps a list of cases instead of one. Existing profiles migrate on load.

### 0.7.1

**Fixed**
- Speed and red-light camera fines are no longer charged to you while the stolen car still wears its original plate; they go to the registered owner.
- A fully disguised car is no longer seized when RLS arrests you for an unrelated offence.

**Changed**
- The controls menu now describes the key's current uses (parked, moving and dealership cars, storing).

### Earlier versions

- **0.7.0**: Vehicle Theft skill (50 levels, XP for each step of a theft, perks), six theft milestones, the skill on RLS's Skills page. The Underground app's countdowns keep running in every phase.
- **0.6.1**: Carjack civilian cars driving below about 30 km/h.
- **0.6.0**: Underground phone app with listings, timed offers from different buyer types, and negotiation. Replaces the single offer at the garage computer.
- **0.5.3**: An unrepainted stolen car can be recognized by patrols and raided at the handover.
- **0.5.2**: Store by parking inside the garage (or getting out there); reminder near an owned garage.
- **0.5.1**: Parked props are replaced with the real car, so parked cars can be driven.
- **0.5.0**: Immediate pursuit for carjacking; report delay for parked cars depends on missed signals and witnesses. Easier ignition bypass (slower marker, wider zone, a miss costs time instead of ending the attempt) with Space to lock. Fixes for arrests, pursuit mode and garage storage.
