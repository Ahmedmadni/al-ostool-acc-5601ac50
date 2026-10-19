# Gate 81 — Disposable SQL rollout guard and staging hold

This gate is **source-control-only**. It does not install a schema, create a Supabase project, use production credentials, or approve deployment.

## Automated protection

`scripts/check-gate81-migration-order.mjs` checks `.github/workflows/native-tenant-sql-smoke.yml` for all three independent PostgreSQL jobs, the fixed disposable database name, absence of hosted GitHub secrets, a clean database check, no legacy Gate 13–15 or Gate 66 SQL, ordered Gates 71–75, and real Gate 42 before Gate 64 when Gate 64 is compiled. The check is executed in the PR SQL workflow before any PostgreSQL service tests.

This is a **workflow regression guard**, not a SQL parser, test of actual RLS, proof of a restorable backup, or authorization to deploy. The Gate 64 fixture still stubs parts of B4 and Gate 63. Existing tests remain responsible for posting, tenancy and reversals.

## Staging acceptance hold

1. Confirm a separate owner organization, project region, permissions and explicit agreement on nonzero charges. Neither inactive linked project is assumed to be staging.
2. Create an independent, empty Supabase project with synthetic tenants and users only. Never copy company documents, auth data or production keys.
3. Compare actual base schema, account mappings and migrations with the 52-object Gate 79 read-only report. Do not treat catalog presence as behavioral verification.
4. Run native SQL against disposable Staging with source-controlled, staged migrations only after a review of dependencies and rollback plan.
5. Confirm project and clearing account codes with finance, validate separated approval/posting actors, reconciliation, reversals, and two-tenant RLS negative tests.
6. Keep production feature flags off and all production DDL/DML blocked until independent written acceptance.

**Explicitly blocked:** legacy Gates 13–15 and Gate 66; unreviewed accounting mappings; Gate 64 as a standalone migration. No production changes were performed for Gate 81.
