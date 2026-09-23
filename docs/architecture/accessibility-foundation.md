# Gate 52 — Accessibility foundation

## Goal

Make the authenticated ONEXA shell predictable for keyboard and assistive-technology users without changing business behavior.

## Behavior

- A bilingual skip link is the first focusable shell control and targets the main content region.
- Route changes move focus to the new main region without forcing a scroll jump.
- The global command palette now exposes a programmatic title and description.
- Command input and shortcut spacing use logical properties for correct RTL and LTR rendering.
- Reduced-motion preferences suppress non-essential animation and transition duration.

## Scope

This gate strengthens the shared shell and command-dialog primitives. Existing authorization, routing, and business calculations are unchanged.

## Data impact

No database migration, seed, feature flag, or production SQL is introduced.
