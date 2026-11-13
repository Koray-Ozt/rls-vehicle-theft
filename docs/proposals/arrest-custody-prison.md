# Arrest, Custody and Prison System (Proposal)

> Status: design proposal only. No gameplay implementation is included in this pull request.

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

## Open technical questions

- Which RLS/BeamNG event definitively signals arrest completion?
- Which supported RLS API advances career time safely?
- Where are map-specific police-station positions available?
- What is the authoritative stolen-vehicle state across garage and Underground systems?
- Which fines and seizures are already handled by RLS?
