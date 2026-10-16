# Gate 76 — Ephemeral PostgreSQL acceptance smoke (G71–G75)

**Goal:** move beyond static TypeScript / SQL-text pattern checks to a REAL PostgreSQL 16 parser, DDL engine, constraint checker and a synthetic two-tenant authorization smoke **without touching customer production**.

## Run

Opening a PR against `main` triggers `.github/workflows/native-tenant-sql-smoke.yml`, which starts an isolated PostgreSQL 16 service with database `onexa_gate_test`. There are **no cloud service-role secrets** and no connections to an external Supabase project. The job:

1. Creates synthetic tenant, legal-entity, branch, workspace, membership, role, customer, contract, G42 and B4 parent structures from `scripts/sql-fixtures/native-maintenance-parent-schema.sql`. These are **structural test doubles**, NOT a copy of the production schema and NOT a restored company backup.
2. Applies actual source SQL `gate71_onexa_tenant_company_module_scopes.sql` through `gate75_native_maintenance_unpaid_source_review.sql` sequentially with `psql -v ON_ERROR_STOP=1` to catch invalid DDL, missing relations/columns, trigger/RPC compilation blockers, composite FK/index problems and SQL dependency-order failures.
3. Executes `scripts/sql-fixtures/native-maintenance-two-tenant-smoke.sql` under roles matching `authenticated`, with different synthetic tenant JWT IDs. It tests a site/asset/order per tenant, a separated creator/approver/assignee/acceptor flow, registration and independent financial review of a new unpaid source, cross-tenant work-order creation/source registration denial and RLS isolation.
4. Simulates one **already-posted** G42 document + B4 journal in this synthetic test database (does not call real G42 posting), then verifies the Gate74 attribution and Gate75 provenance link, idempotency, and exclusion of a subsequently reversed journal. Test transaction ends with `ROLLBACK`.

The CI runner is deleted after the workflow. This task cannot deploy a schema or change production. Use `npm run check:gate76-ephemeral-postgres-smoke` for a fast, source-only safety check; the **GitHub Actions PostgreSQL job** is what performs real DDL execution.

## Critical limitations

This is a **smoke test, NOT a production installation signoff**. It validates native SQL against simplified synthetic ONEXA parent tables, not every live constraint, status enum, policy, real Gate42/64 workflows or financial posting. It does not replace actual finance reconciliation, stock movement compensation, tax treatment, independently verified unpaid supplier evidence, actual two-tenant staging/UAT, restore test, DBA maintenance window or business user acceptance.

Specifically, use a disposable **clone of the actual customer schema** for the final compatibility and negative-isolation acceptance. Always require database review, tested backups, correct module-role mapping, controlled index lock budget, complete postchecks and finance/operations/security approval. Never run these `sql-fixtures` against a customer environment; they create test roles and simplified tables.

**STOP** if any smoke stage fails or the live schema differs from the test doubles. No Gate71–75 production DDL was executed during this work.
