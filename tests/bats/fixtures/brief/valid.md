---
topic: checkout-v2
created: 2026-07-17
status: ready
inputs:
  - inputs/PRD.md
---

# Brief: checkout-v2

## Essence
Users abandon the checkout at the payment step because the form spans four
screens and loses state on every validation error.

## Goal & Impact
Cut checkout abandonment from 38% to 25% within one quarter, recovering an
estimated 1.2M RUB of monthly revenue.

## References
- inputs/PRD.md — product requirements for the current checkout

## Solution (JTBD)
When I am ready to pay, I want to confirm and pay on a single screen, so that
I finish before I reconsider.

## Scenarios
- A returning user pays with a saved card in two taps.
- A new user enters card details and recovers from a declined payment without
  re-entering the whole form.

## Constraints
- No new payment provider in this iteration.
- The existing anti-fraud call stays synchronous.

## UX
A single-page checkout with an inline error summary pinned above the pay
button; field state survives every validation round-trip.

## Done Criteria
- Abandonment measured below 25% for two consecutive weeks.
- No regression in payment success rate.

## Attachments
- [PRD.md](inputs/PRD.md)
