# ONEXA product experience refresh

## Reference review

The reviewed accounting interface succeeds through a restrained visual system: a light right sidebar, generous spacing, thin borders, consistent line icons, a compact Arabic typeface, and one soft accent color for selection and primary actions. Large settings dialogs keep navigation visible while the content scrolls independently.

## ONEXA direction

This refresh applies those principles as an original ONEXA system:

- IBM Plex Sans Arabic for compact, readable Arabic labels and figures.
- Manrope for Latin text and numeric dashboards.
- A white RTL desktop sidebar with quiet borders and indigo selection states.
- Lucide icons at a consistent 1.8 stroke where the shell establishes navigation hierarchy.
- A soft neutral canvas, white cards, 12px radii, and low elevation.
- A clearer header with the active application, tenant, plan, search, and keyboard hint.
- Refined controls, dialogs, tabs, inputs, KPI cards, and focus states.
- Dark mode retained with its existing contrast model.

## Product rules

1. Purple and indigo indicate active navigation and primary actions, not decoration.
2. Status colors retain semantic meaning: green for success, amber for attention, and red for destructive or critical states.
3. Empty states must explain the missing data and present one relevant action.
4. Desktop pages use the full available width while keeping 24–36px content padding.
5. New navigation icons should come from Lucide unless a branded illustration is needed.
6. Settings that exceed one screen should use a large dialog or dedicated route with persistent section navigation.

## Scope

The first increment updates the authenticated shell and shared primitives. Existing screens inherit the new tokens without changing business logic. Dashboard and settings layouts can then be refined module by module using the same system.
