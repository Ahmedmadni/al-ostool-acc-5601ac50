# Gate 49 — Mobile navigation

## Goal

Keep the complete ONEXA application model usable below the desktop `md` breakpoint, where the fixed sidebar is intentionally hidden.

## Behavior

- A labeled menu button opens a direction-aware navigation sheet from the logical reading side.
- The sheet contains the app launcher and every accessible application group and page.
- Current-page styling mirrors the desktop navigation and route selection closes the sheet.
- The signed-in identity, assigned roles, and sign-out action remain available at the bottom.
- A compact search button exposes the Gate 48 global command palette on phone widths.
- Secondary header actions collapse below `sm` to preserve touch targets and avoid horizontal overflow.

## Authorization boundary

Mobile navigation renders the existing `allGroups` collection. Tenant availability and module `view` permissions are therefore identical across desktop navigation, mobile navigation, and global search.

## Data impact

This is a responsive shell enhancement only. It requires no database migration, seed, or feature-flag change.
