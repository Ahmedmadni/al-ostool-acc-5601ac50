# Gate 50 — Application launcher workspace

## Goal

Make the application launcher the fastest entry point into ONEXA while preserving subscription and role boundaries.

## Experience

- The hero now summarizes accessible applications, available business categories, and pinned applications.
- Category filters provide a compact business-area view and work together with bilingual search.
- Favorites stay prominent when no filter is active.
- Empty results provide a direct reset action.
- Accounting integration and subscription governance remain visible, but follow the primary launch workflow instead of interrupting it.

## Authorization boundary

Counts, filters, favorites, and category results all derive from the existing `allowed` application collection. Subscription eligibility is checked first with `tenant.canUseModule`, then legacy company guards and permission-module `view` checks are applied.

## Data impact

Favorites continue to use the existing browser-local preference. No database migration, seed, feature flag, or production SQL is introduced.
