# ONEXA application information architecture

Status: Gate 33 navigation foundation implemented on 20 September 2026.

## Navigation model

ONEXA uses two levels instead of exposing every page in one continuously expanding sidebar:

1. **App launcher** — the complete catalogue filtered by subscription entitlements and role permissions.
2. **Contextual sidebar** — only the navigation of the current application is displayed.

The application switcher in the sidebar moves between modules without returning to a long accordion. The top bar retains global actions and displays the active workspace and plan.

## Global top bar

- Active workspace and plan.
- Global search.
- Language switcher.
- Calculator and financial copilot.
- Notifications, notes, account, and theme.

Legal entity, branch, and fiscal period selectors are introduced when their shared master-data queries are available. They must use trusted tenant-scoped records rather than static values.

## App launcher rules

- Display only modules allowed by both subscription entitlement and user permission.
- Search Arabic and English names regardless of the active interface language.
- Keep favorites local to the browser until user-preference storage is available.
- Use bilingual category, application, description, status, and action labels.
- Never use a tenant or customer name as a product-level module name.

## Directionality

- Arabic uses RTL and English uses LTR.
- Use logical spacing and positioning utilities.
- Numeric, email, tax, and registration values retain LTR direction inside Arabic pages.
- Icons that imply direction rotate when required; neutral icons do not.

## Responsive behavior

- Desktop: persistent contextual sidebar and global top bar.
- Tablet: contextual sidebar remains available while labels stay concise.
- Mobile: bottom navigation and mobile app launcher provide the same permission-filtered entry points.
- No desktop navigation item may be the only way to reach a permitted application.
