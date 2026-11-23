# Value-Based Ignition Bypass Difficulty (Proposal)

> Design proposal only; no gameplay implementation in this PR.

## Goal

Make the existing ignition bypass minigame scale with the stolen vehicle's value, so higher-value vehicles are generally harder to start without making low-value vehicles frustrating.

## Proposed behavior

- Read the vehicle's authoritative market/value estimate from the existing RLS/BeamNG vehicle data; verify which value is available at theft time.
- Map vehicle value to a small number of configurable difficulty tiers with sensible minimum/maximum limits.
- Adjust existing minigame parameters (for example target-zone width, marker speed, available time or required successful signals) rather than introducing an unrelated mechanic.
- Preserve the existing Vehicle Theft skill perks and ensure their bonuses still matter at every tier.
- Avoid extreme difficulty spikes at tier boundaries and do not make any car impossible to steal.
- Use a safe default tier when the vehicle's value is missing or unreliable.
- Keep current alarm, failed-attempt, cooldown and cancellation behavior intact.

## Acceptance criteria

1. More valuable vehicles generally present a more difficult ignition bypass challenge.
2. Lower-value cars remain accessible to new players.
3. Skill perks continue to improve the experience across tiers.
4. Missing/invalid valuation data falls back safely.
5. Difficulty remains consistent for repeat attempts on the same vehicle and cannot be trivially rerolled.
6. The feature does not alter vehicle resale values or police behavior unless separately designed.

## Open design questions

- Which vehicle valuation is authoritative and stable across career profiles?
- What tier boundaries and minigame parameters provide balanced difficulty?
- Should vehicle security/age eventually be a separate modifier? Not included in the initial scope.
