# Underground Net Profit Indicator (Proposal)

> Design proposal only. No in-game UI or calculation code is implemented in this PR.

## Goal

Add a compact, easy-to-read **estimated net profit** indicator to the Underground phone app so players can judge whether selling a stolen vehicle is actually worthwhile after their expenses.

## Proposed behavior

- Show a small net-profit estimate near the vehicle's sale/listing price and update it when the asking price changes.
- Calculate **estimated net profit = expected sale proceeds - attributable costs**.
- Include applicable expenses already incurred for the vehicle, such as vehicle identity change, repainting, and any other tracked theft-related expenses. Avoid guessing or counting expenses not actually recorded by the mod/RLS.
- If a buyer offers a different price, show the profit based on that offer; for negotiation, recalculate when the offer changes.
- Distinguish **estimated** profit before a sale from **realized** profit after a completed sale.
- Handle negative outcomes as a loss and zero as break-even.
- Do not treat sale price as profit or double-count an expense.
- Where cost history is incomplete, label the figure as partial/estimated rather than presenting a falsely precise amount.

## UX constraints

- Small, unobtrusive label in the existing Underground UI; no extra modal or screen.
- Use the existing UI formatting and currency conventions.
- Show positive, negative and break-even values clearly, without relying only on color.
- Avoid displaying a profit number for actions where no sale proceeds are available.

## Technical checklist

- Locate the authoritative Underground pricing/offer state and vehicle-specific expenditure records.
- Check which identity-change, painting, workshop, fines or other expenses are available per vehicle; decide explicitly which are attributable to a sale.
- Keep the display reactive to asking-price edits, offers and completed transactions.
- Test multiple concurrent stolen vehicles to ensure costs never bleed between cases.
- Test missing costs, cancelled/refunded workshop operations, losses and sale completion.
- Preserve compatibility with the current RLS Career Overhaul UI integration.

## Acceptance criteria

1. The player can see an estimated net profit or loss directly in Underground.
2. Changing the asking price or accepting a different offer updates the figure correctly.
3. Recorded vehicle-specific costs are deducted once, including refunded/cancelled costs correctly.
4. Figures for separate vehicles remain independent.
5. The label remains compact and consistent with the phone app's current design.

## Open decision

Should police fines count as vehicle-specific expenses only when they are actually charged and attributable to that vehicle, or be excluded from the displayed trade profit? Decide after inspecting the existing expense records.
