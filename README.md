# RLS Vehicle Theft

Version 0.7.0 adds vehicle theft to RLS Career Overhaul. Take a vehicle from the street or a dealership, store it in an owned garage, change its identity, and sell it to underground buyers from the **Underground** phone app. Police, vehicle damage, workshop costs, and fines can turn a sale into a loss.

This is an unofficial add-on. It is not affiliated with RLS Modding or BeamNG GmbH.

## Dependencies

This mod is an add-on for RLS Career Overhaul. It does **not** include RLS and does nothing without it.

| Dependency | Version | Required | Notes |
|---|---|---|---|
| [BeamNG.drive](https://www.beamng.com/game/) | 0.40.5 | Yes | The version the mod was built and played on. |
| [RLS Career Overhaul](https://github.com/RLS-Modding/rls_career_overhaul) | 2.8.0 Hotfix | Yes | Install and enable it separately. Other RLS versions are untested. |
| An RLS career profile | — | Yes | Theft only works in an active RLS career, with at least one owned garage that has a free slot. |

At runtime the mod calls RLS's career, garage, police, parking, marketplace, payment, skills and milestone systems. The Underground phone app also loads two files from inside RLS: the negotiation screen (`components/negotiation/NegotiationChatWindow.vue`) and the phone screen helper (`composables/usePhoneScreen.js`). An RLS update that renames or moves these may break the mod until it is updated.

The mod has no other dependencies and does not modify any RLS or BeamNG file.

## Installation

1. Install and enable **RLS Career Overhaul 2.8.0 Hotfix**.
2. Download `rls_vehicle_theft_<version>.zip` from this repository's [Releases](../../releases) page. Do not unpack it.
3. Put the ZIP in your BeamNG user folder under `mods` (for example `%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods`).
4. Remove any earlier `rls_vehicle_theft_*.zip` from that folder, enable the mod in the Mod Manager, and restart the game.
5. In your RLS career, install **Underground** from the phone's App Store.

To build the ZIP yourself, compress the folders `gameplay`, `lua`, `scripts`, `settings` and `ui` so they sit at the root of the archive.

## Playing

1. **Take a vehicle.** In RLS Career, walk up to the door of a parked or stopped civilian vehicle, press **Ctrl + Shift + J** and stay beside it for 4 seconds. You can also carjack a civilian car that is still driving below about 30 km/h: step next to it (within about 6 m) and press the shortcut. The driver brakes to a stop; stay next to the car for 2.5 seconds and it is yours. Walk away first and the car drives off again. The same shortcut works while inspecting a dealership vehicle or driving it during a dealership test drive.
2. **Start the engine.** A stopped traffic vehicle already has its engine running, so you take it without the bypass. If the engine is off, select **Begin** on the **Ignition Bypass** screen. Press **Lock signal** (or **Space**) when the white marker is in the green zone. Match all three signals within 25 seconds. A miss costs 4 seconds; if the time runs out, wait 8 seconds before trying again. Vehicle Theft perks widen the target zone and shorten the miss penalty. If the engine starts but the parking brake is on, release it before driving.
3. **Store it.** Lose any active pursuit and park the vehicle inside a garage you own. Press **Ctrl + Shift + J**, or simply get out; the vehicle is stored automatically. It uses a normal garage slot. A vehicle left at the entrance is not stored, because the garage computer only lists vehicles inside the garage.
4. **Change its identity and repaint it.** At the garage computer, select the vehicle and choose **Change vehicle identity**. This also gives it a new plate. The work costs 23% of the car's value (at least $1,200) and takes 150 seconds; Vehicle Theft perks make it cheaper and faster. The Underground app counts down the remaining time. Repaint it with the RLS painting option on the same computer: the theft report describes the colour it had when you stored it.
5. **Sell it from the Underground phone app.** Install **Underground** from the phone's App Store once. When the identity change is done, open the app, set an asking price and choose **List for sale**. Buyers send offers over time; each offer expires after a few minutes, and up to four can wait at once. For each offer choose **Accept**, **Decline** or **Negotiate**. You can sell from anywhere; the vehicle is handed over and the money is paid at once.

### Asking price and negotiation

The app shows the vehicle's underground value: about 61% of its normal sell value, or 54% while the theft is still fresh (Vehicle Theft perks raise it by up to 15%). Listing below that value brings offers sooner and closer to your price; listing well above it makes buyers rarer and keeps their offers near the underground value. This follows the RLS marketplace.

Negotiation uses the RLS negotiation screen. Each counter-offer costs the buyer patience, more so the further your price is from the underground value. A buyer moves part of the way toward your price, never past their budget, and walks away when their patience runs out, which removes the offer. Buyer types differ: chop shops pay least and lose patience fastest, exporters pay most and stay longest.

## Vehicle Theft skill and milestones

**Vehicle Theft** is an RLS career skill with 50 levels on the same XP curve as RLS's other skills. It appears on the Skills page and in the phone's Skills app, and RLS adds its usual level milestones for it.

| Action | XP |
|---|---|
| Take a car from its driver | 12 |
| Take a parked car (bypass with a miss / without a miss) | 15 / 20 |
| Take a dealership car (inspection / test drive) | 15 / 20 |
| Store it in your garage | 10 |
| Lose the police in a stolen car (first three times per car) | 10 |
| Finish the identity change | 5 |
| Underground sale | 15 + 1 per $400 of the price (at most +45), +5 when negotiated above the opening offer |

A full theft usually earns 60–100 XP: level 5 takes roughly 15–20 thefts and level 10 roughly 60.

| Level | Perk |
|---|---|
| 3 / 10 / 25 | Ignition bypass target zone 10% / 20% / 30% wider |
| 5 | Getting into a parked car takes 3 seconds instead of 4 |
| 8 / 18 / 30 / 45 / 50 | Underground buyers value your cars 3% / 6% / 10% / 12% / 15% higher |
| 10 | A missed ignition signal costs 3 seconds instead of 4 |
| 12 / 25 / 40 | Identity changes cost 10% / 20% / 30% less |
| 15 | A parked car taken cleanly is noticed 25% later |
| 20 / 40 | Identity changes take 120 / 90 seconds instead of 150 |
| 30 | Underground offers arrive 15% sooner |
| 35 / 50 | Unrepainted car: patrol recognition 22% / 15% instead of 30%, handover raid 15% / 10% instead of 20% |

Theft milestones appear with RLS's general milestones and pay money when claimed: **Car Thief** (vehicles stolen), **Carjacker** (cars taken from their drivers), **Clean Hands** (ignitions bypassed without a miss), **Ghost Driver** (police lost in a stolen car), **Fence** (underground sales) and **Underground Earnings** (total underground income). Rewards follow RLS's own milestone payouts: $100 per tier for the first four and $250 per tier for the two selling milestones. Counting starts with this version; earlier thefts are not included.

## Consequences

- **Taking a traffic vehicle from its driver** is reported at once, and the nearest police unit starts a pursuit right away, even if it has not seen you yet.
- **Taking a parked vehicle** goes unnoticed for 90–180 seconds if you match every signal cleanly. Each missed signal trips the alarm and shortens that time. Two or more nearby traffic vehicles act as witnesses and shorten it further.
- Once a vehicle is reported, any patrol that spots it within about 160 m starts an RLS pursuit. After you evade a pursuit, patrols ignore the vehicle for 45 seconds.
- A new identity hides the plate, not the paint. If the vehicle still has the colour it had when you stored it, each new patrol that sees you driving it has a 30% chance to recognize it and start a pursuit, and the underground handover has a 20% chance to be raided, which seizes the vehicle and charges the theft fine. The Underground app marks such a vehicle as risky.
- An official marketplace listing can be published normally. If you try to complete the title transfer, the sale is canceled, the listing is removed, the vehicle is seized, and a fine is charged. The sale pays out nothing.
- Stealing a vehicle from a company-affiliated dealer reduces that company's RLS reputation by 120 points during an inspection or 220 points during a test drive.
- Test-drive theft suspends test-drive privileges at that dealership. A later investigation can issue a fine even after an underground sale.

## What the mod contains

Everything lives in this mod's ZIP; no RLS file is edited. BeamNG merges all mods into one virtual file system, and RLS discovers phone apps and skills by scanning shared folders, so it reads this mod's files as if they were its own.

| File in the ZIP | Purpose |
|---|---|
| `lua/ge/extensions/rlsVehicleTheft.lua` | All logic: theft, ignition, storage, identity change, police, underground market, XP, perks and milestones |
| `gameplay/overhaul/domains/careerSkills/skills/vehicleTheft/info.json` | The Vehicle Theft skill: 50 levels and their perk cards |
| `gameplay/overhaul/phone/apps/rls-underground.json` | The Underground phone app definition |
| `ui/ui-vue/mods/rls_vehicle_theft/UndergroundApp.vue` | The Underground app screen |
| `ui/ui-vue/mods/rls_vehicle_theft/IgnitionBypass.vue` | The ignition bypass screen |
| `ui/images/rls_vehicle_theft/underground.png` | The Underground app icon |
| `gameplay/overhaul/ui/routes/rls-theft-routes.json` | The ignition screen's UI route |
| `lua/ge/extensions/core/input/actions/rls_vehicle_theft.json`, `settings/inputmaps/keyboard_rls_vehicle_theft.json` | The **Ctrl + Shift + J** action and binding |
| `scripts/rls_vehicle_theft/modScript.lua` | Loads the extension |

Where the mod changes RLS behaviour (blocking official sales of stolen cars, suspending test drives, adding the skill to the Skills page), it wraps the RLS function while the game runs and restores it when the extension unloads.

## Current limits

Parked cars in RLS are simplified props with no engine or drivetrain. When you take one, the mod replaces it with the real model of the same car, in the same place, paint and plate, using that model's default configuration. The Ardente and Tograc props have no real model in the base game, so they cannot be taken.

The mod supports one active vehicle theft case at a time. Store the stolen vehicle before leaving the session. An unstored vehicle does not survive a reload, and the case can result in a fine when you return.

The mod ships no automated tests. Theft, the ignition screen, storage, the identity change and the Underground app have been played in BeamNG 0.40.5 with RLS 2.8.0. The Vehicle Theft skill, its perks, the theft milestones and the identity countdown fix in 0.7.0 have been checked only by reading the code against RLS, not yet in the game. The Underground app reuses RLS's negotiation component and phone screen helper, so a future RLS update that moves those files would break the app's negotiation screen.

## License

This mod is released under the [MIT License](LICENSE). The license covers this mod's own files only. RLS Career Overhaul and BeamNG.drive are separate works under their own licenses and are not included.

## Changes

- **0.7.0**: Vehicle Theft skill (50 levels, XP for each step of a theft, perks), six theft milestones, the skill on RLS's Skills page. The Underground app's countdowns keep running in every phase.
- **0.6.1**: Carjack civilian cars driving below about 30 km/h.
- **0.6.0**: Underground phone app with listings, timed offers from different buyer types, and negotiation. Replaces the single offer at the garage computer.
- **0.5.3**: An unrepainted stolen car can be recognized by patrols and raided at the handover.
- **0.5.2**: Store by parking inside the garage (or getting out there); reminder near an owned garage.
- **0.5.1**: Parked props are replaced with the real car, so parked cars can be driven.
- **0.5.0**: Immediate pursuit for carjacking; report delay for parked cars depends on missed signals and witnesses. Easier ignition bypass (slower marker, wider zone, a miss costs time instead of ending the attempt) with Space to lock. Fixes for arrests, pursuit mode and garage storage.
