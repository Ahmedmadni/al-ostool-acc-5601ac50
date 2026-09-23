# Gate 48 — Global command palette

## Goal

Turn the shell search affordance into a fast, keyboard-first navigation surface without creating a second navigation model.

## Behavior

- The header search button opens the palette by click or with `Ctrl/Cmd + K`.
- Search covers the Arabic title, English title, application group, and route path.
- Results are grouped by application and keep ONEXA's restrained line-icon treatment.
- Selecting a result uses TanStack Router navigation and closes the dialog.
- The empty state is localized in Arabic and English.

## Authorization boundary

The palette consumes `allGroups`, the same tenant- and permission-filtered collection used by the application switcher and side navigation. It therefore cannot reveal routes removed by `tenant.canUsePath` or module `view` permissions. Route enforcement remains the responsibility of the existing authenticated route and permission layers.

## Data impact

This gate is presentation-only. It adds no database objects, migrations, feature flags, or production rollout steps.
