# Gate 54 — Professional print and PDF output

## Goal

Produce clean management and accounting printouts from existing screens using the browser print-to-PDF flow.

## Behavior

- Printed authenticated pages receive an ONEXA header with workspace, application, and plan context.
- A4 portrait sizing and controlled margins are applied globally.
- Navigation, dialogs, buttons, connectivity notices, and decorative shell elements are excluded.
- Table headers and footers repeat across pages.
- Rows, cells, images, charts, and cards avoid page breaks where practical.
- Print colors are preserved while shadows are removed for cleaner output.

## Scope

This gate improves presentation only. Individual statutory statements may still define specialized report templates and pagination where required.

## Data impact

No database migration, seed, feature flag, or production SQL is introduced.
