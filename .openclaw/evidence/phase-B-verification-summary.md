# Phase B Verification — Constraint Capture Upgrade

## Passing smoke
- Ran `./scripts/plan.sh '5 days in Tokyo for a couple under $2500 relaxed pace near Shinjuku vegetarian food avoid rainy outdoor plans must be open on Monday'`.
- Verified JSON fields for `budget.cap`, `budget.cap_fit`, `constraints.trip_pace`, `constraints.neighborhood_preference`, `constraints.opening_hours_sensitivity`, `constraints.food_preference`, and `constraints.weather_sensitivity`.
- Output artifact: `.openclaw/evidence/phase-B-constraint-smoke.json`.

## Static trust smoke
- Ran `./scripts/socket-review-check.sh`.
- Output artifact: `.openclaw/evidence/phase-B-socket-review.txt`.

## Note
- A separate baseline example containing the phrase `mid-range` tripped the script's existing strict input gate during smoke setup; this run did not broaden the scope to input validation refactoring.
