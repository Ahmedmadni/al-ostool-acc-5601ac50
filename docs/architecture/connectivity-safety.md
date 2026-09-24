# Gate 53 — Connectivity safety

## Goal

Prevent users from treating stale screens as current or attempting sensitive accounting actions while the browser is offline.

## Behavior

- The authenticated shell listens to native online and offline events.
- Offline state displays a persistent, assertive warning below the sticky header.
- The warning explicitly advises against posting or approving transactions.
- Reconnection displays a temporary success state and refetches active React Query data.
- The component is bilingual and exposes machine-readable connectivity state.

## Control boundary

This is a user-interface safety control. Server-side authorization, validation, idempotency, and transaction rules remain authoritative.

## Data impact

No database migration, seed, feature flag, or production SQL is introduced.
