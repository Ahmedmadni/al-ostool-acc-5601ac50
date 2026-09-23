# Gate 51 — Executive decision-data readiness

## Goal

Ensure the executive dashboard distinguishes verified zero activity from unavailable data. A decision surface must never silently convert a failed source query into a financial zero.

## Behavior

- Eight financial and operational sources report their row count, latest period or date, and readiness state.
- Query failures are surfaced as unavailable sources and affected KPI values render as an em dash rather than a fabricated zero.
- Empty sources remain valid and show zero rows.
- Revenue/profit and cash-flow charts have action-oriented empty states that lead to imports or treasury workflows.
- Loading skeletons preserve layout while source readiness is being resolved.

## Accounting control

This change is presentation and control logic only. Existing KPI formulas and source tables are unchanged. The readiness strip makes source completeness visible before management interprets the dashboard.

## Data impact

No database migration, seed, feature flag, or production SQL is introduced.
