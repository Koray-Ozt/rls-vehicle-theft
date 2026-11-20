# Underground Vehicle Delivery Contracts (Proposal)

> Design-only proposal. This PR does not implement gameplay or UI changes.

## Goal

After accepting an Underground buyer's offer, sometimes let the buyer request **vehicle delivery to a marked location** in exchange for additional money and Vehicle Theft XP. This adds optional driving risk to the existing phone-based sale flow.

## Proposed flow

1. Player accepts a normal Underground buyer offer.
2. A configurable fraction of eligible buyers ask for delivery, showing the destination, estimated distance, extra payment and bonus XP.
3. Player can **decline** and proceed with the existing instant-sale flow, or **accept** the delivery contract.
4. If accepted, the sale is pending: keep the vehicle in the player's possession, reserve the transaction, and show a destination marker/navigation objective.
5. Player drives the correct vehicle to a verified, reachable drop-off area and completes delivery.
6. Only on successful handoff, remove the vehicle and pay **base sale price + delivery bonus**, plus delivery XP.
7. If the vehicle is seized, destroyed, or the contract is cancelled/failed, no delivery bonus or XP is awarded. Define clearly how any pending base sale is handled before implementation.

## Rewards and balance

- Delivery request frequency should be configurable; **25%** is an initial balancing suggestion, not a fixed requirement.
- Bonus money can scale with route distance and risk, with reasonable minimum/maximum caps.
- Reward XP only after successful delivery; optionally grant a small condition-based bonus for a relatively undamaged vehicle.
- Prevent exploiting repeated offers, map reloads, cancellations or save/load to duplicate payouts.
- Make the additional reward worth the time and risk without rendering ordinary sales pointless.

## Technical constraints

- Reuse the current Underground negotiation, buyer-offer and sale lifecycle rather than bypassing it.
- Find safe, map-specific drop-off points with valid vehicle access. Never generate arbitrary coordinates inside buildings, on roofs or off-road.
- Track contract and target vehicle identity across saves, reloads, garage transitions and pursuit states.
- Do not pay or delete the vehicle when the player merely accepts a delivery request.
- Integrate with existing heat/police behavior, vehicle ownership, garage storage and undercover sting rules. **Undercover offers must not become an unintended safe payout path.**
- Provide a fallback to the normal sale when no valid delivery destination exists.

## Acceptance criteria

- Eligible accepted offers can present an optional delivery request.
- Declining preserves the current instant-sale behavior.
- Accepting defers the payment and vehicle transfer until the correct vehicle reaches a valid destination.
- Successful delivery awards the correct sale amount, extra payment and XP exactly once.
- Failure, police seizure and interrupted sessions cannot duplicate payouts or strand a vehicle in an inconsistent state.
- The destination is reachable by car on supported maps.
- The Underground UI clearly shows pending delivery, destination and rewards.

## Open decisions

- Exact offer frequency, bonus formula, XP values and delivery time limits.
- Whether declining the delivery request affects buyer reputation (default proposal: no).
- Whether optional vehicle-condition bonuses should be included in the first release.
- How to resolve interrupted deliveries without punishing players for technical errors.
