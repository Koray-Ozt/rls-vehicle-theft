# Changelog

Release history before 0.10.0. For the current release, see the [README](README.md#changes).

## Releases

### 0.9.6

This release fixes a stolen car that could not be stored in some owned garages and moves the mod to RLS 2.8.1. Saves from 0.9.5 load without any action.

**Fixed**
- **A stolen car is stored in garages without doors.** Dockside Garage, the starting garage on some profiles, was never found "within reach" of a car parked right at its computer, so nothing happened and no message appeared. RLS places a garage without doors at the centre of its zone, at the terrain height; under a pier or platform that height is 0 while the garage is at 75, so the 3D distance to the car was about 75 m against a 35 m limit.
  - The distance to a garage is now measured on the map, ignoring height.
  - Every owned garage is checked, not only the one RLS reports as closest in 3D, which the same height error could also get wrong.

**Changed**
- The mod writes what it decides about storing a car to `beamng.log` (tag `rlsVehicleTheft`): the closest garage and its distance whenever that changes, each reason a car is not stored, and the result of a store. A refusal used to exist only as a seven-second message on screen.
- RLS Career Overhaul 2.8.1 is now the supported version. Every RLS function the mod calls, the phone app and notification channels, the shipped Skills file and the negotiation screen were compared with 2.8.0 Hotfix and found compatible. At the time of the 0.9.6 release, theft, the ignition screen and storing a car had been played on 2.8.1; the identity change, the chop shop and the Underground app had been checked only by reading the code. See 0.10.0 above for the later in-game checks.

**Upgrading from 0.9.5**
- Remove `rls_vehicle_theft_0.9.5.zip` (or any older version) from your `mods` folder before adding 0.9.6. Saves load without any action.

### 0.9.5

This release adds taxi theft, shows the estimated net profit of a sale in the Underground app, and keeps the version of a stolen parked car instead of turning it into the model's default configuration. Saves from 0.9.4 load without any action.

**Added**
- **Taxi theft.** Idle RLS taxis can now be taken from their drivers like any civilian car in traffic. A cab working a ride for you (on its way, waiting or driving you) is left alone.
  - The driver's cash comes with it: $60–$240, paid at once.
  - A stolen taxi is a commercial vehicle, so its pursuits start at RLS wanted level 3 instead of 1, through RLS's own pursuit levels.
- **Phone notifications for finished workshop jobs.** When the crew finishes stripping a car for parts, or the workshop finishes an identity change, the Underground app sends a phone notification with the car's name (and the payment for parts). They use their own **Workshop** channel, which can be muted in the phone's notification settings apart from buyer offers.
- **Estimated net profit in the Underground app.** The asking price, each buyer offer and the sold result now show the net after the car's recorded expenses, as profit, loss or break-even (worded, not only colored).
  - Tracked per car: the identity change fee (taken back out if the workshop refunds it) and RLS repaint charges. Cars changed or repainted before this tracking existed are labeled "partial costs". Police fines are not counted.

**Changed**
- The taxi theft message is split in two: the driver's cash on its own short line, then the wanted level and what to do next.
- The code is split from one 2,600-line file into a small extension file and 15 parts under `lua/ge/extensions/rlsVehicleTheft/`, built the way RLS builds its taxi service. All gameplay tunables are in `config.lua`. Behaviour is unchanged.

**Fixed**
- **A stolen parked car keeps its version.** A parked car (or a car in simplified traffic) used to turn into its model's default configuration when taken, so a BX-Series LX Coupe became a 200BX Type-L with a manual gearbox and every D-Series pickup a D15. It now becomes the matching real configuration: the same body, trim level and, where the game has one, an automatic gearbox.
  - Cherrier Ardente and Tograc parked cars can now be taken too. They are versions of the Vivace model, and the mod used to look for a model of their own name.
- Taking a car from its driver (a taxi or any car in traffic) no longer shows a second "reported stolen" message a second later. It replaced the theft message before it could be read, so the taxi's police warning was barely visible.

**Upgrading from 0.9.4**
- Remove `rls_vehicle_theft_0.9.4.zip` (or any older version) from your `mods` folder before adding 0.9.5. Saves load without any action.

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
