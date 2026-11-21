# Architecture

## Runtime and ownership

`scripts/rls_vehicle_theft/modScript.lua` loads the `rlsVehicleTheft` BeamNG GE extension. The extension owns theft cases, police interactions, garage workflows, identity changes, underground offers, and skill progress integration. It calls RLS career services for inventory, garages, payments, police, marketplace values, and progression; RLS files are not edited at runtime.

Career-owned theft data is saved in `/career/rlsVehicleTheft.json` inside the active career slot. Each case stores its theft source, expected police report time, current workflow phase, optional inventory vehicle ID, identity and paint state, and underground listing. Runtime-only state includes the active negotiation, selected phone-app case, and the live vehicle ID during a theft in transit.

## Underground app flow

The Underground Vue app requests case data from `rlsVehicleTheft.getUndergroundState()` and receives refreshes over the `RlsTheftUnderground` bridge event. UI actions call extension functions through the game Lua bridge. Lua remains authoritative for case state, calculations, offers, and sale outcomes; the Vue app renders the returned view model.

## Vehicle heat

Police reporting and underground heat are separate timestamps on each case. `reportAt` preserves the theft-specific delay before the police report. `heatHotUntil` and `heatWarmUntil` control underground pricing: Hot pays 54% for two minutes, Warm pays 58% for four more minutes, and Cold pays 61%, before the existing skill multiplier. A patrol sighting that starts a pursuit or recognizes the original paint resets both heat deadlines. Existing saved cases without the new fields receive equivalent deadlines from `reportAt` when loaded.

The view model includes the current heat stage, remaining time to the next stage, value multiplier, and explanatory text. Changing the plate while keeping the reported paint caps the stage at Warm. A changed plate and paint are already considered fully disguised by the police logic and therefore show as Cold. Hot and Warm offers use buyer-specific risk messages; offer values use the heat-adjusted underground value at offer generation time.

## Arrest and custody

`custody.lua` handles arrests that confirm a theft. It saves the custody record and the list of linked stolen-car counts before seizing their cases, so a resumed transfer can finish the search without counting a car twice. A car with a new identity and paint remains outside the search. The saved `state.custody.stage` drives transfer, sentencing, sentence service and release; `Custody.vue` renders the current stage and sends token-bound choices back to Lua. A closed session resumes the saved stage on the next profile load.

Sentencing combines the counted theft fines and open test-drive investigations. The lawyer choice determines the payable fine, fee and sentence length. Serving advances the mod's play-time clock and, when RLS dynamic weather is available, its world calendar in steps of up to 12 game hours. Without dynamic weather, only the time of day moves. West Coast has a configured police-station destination; other maps use the nearest garage until a station is configured.

## External integrations

The extension wraps selected RLS functions to block official title transfer of stolen vehicles, track selected garage and marketplace actions, and add Vehicle Theft progression data. Wrappers are installed through `bindRls()` and restored when the extension unloads. The Underground app reuses RLS's negotiation component and phone-screen helper from the patched UI tree.

The Underground settings page uses BeamNG's shared `core_input_bindings` controls service to capture a keyboard or button input and save it through the normal input binding diff mechanism. Axis inputs and mouse left/right clicks are excluded. The packaged keyboard inputmap remains the factory default (`Ctrl + Shift + J`). The theft action ignores input while the Underground app is open so a mouse assignment cannot activate during app use.
