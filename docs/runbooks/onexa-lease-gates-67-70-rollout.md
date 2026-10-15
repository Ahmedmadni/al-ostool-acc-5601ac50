# ONEXA ERP — Gates 67–70 safe rollout and reconciliation

**Scope:** Customer Data Plane only (the Al-Ostool tenant database). This is NOT a Control Plane migration.
**State:** Repository packages are present; live Supabase installation, mapping, and acceptance are **NOT VERIFIED**.
**Policy:** Do not enable runtime flags or run unreviewed production writes. Do not run the entire manual package directory.

## 1 — Identify the database, then inventory (read only)

1. Confirm the Supabase project **ref** matches the customer application's `SUPABASE_URL`. The Control Plane must be a different project.
2. Take an independently verifiable backup and confirm a restore procedure before any DDL.
3. Execute `supabase/manual-packages/lease_gates_67_70_readonly_preflight.sql` in the **correct customer project**.
4. Record every `READY` / `BLOCKED` row and the date/ref. `BLOCKED` is not an instruction to rerun everything.
5. Compare actual DB schema, function signatures, grants and migration history with each package. Check for partial migrations.

This inventory performs **no DDL or DML** and does not execute protected business RPCs. It cannot prove tenant isolation, account mapping, journal reconciliation or runtime flags.

## 2 — Dependencies and deployment order

| Gate | Prerequisite | Manual SQL (only when confirmed absent) | Acceptance | Runtime flag |
|---|---|---|---|---|
| 67 | Gate 15, Gate 64, B2/B3/B4 and real AOA account mapping | `gate67_lease_invoice_receipt_posting.sql` and reviewed `gate67_aoa_lease_account_mapping.sql` | `gate67_postcheck.sql`, rollback smoke, maker/checker, GL match | `VITE_ENABLE_ONEXA_LEASE_ACCOUNTING` |
| 68 | Gate 67 verified | `gate68_lease_schedule_reconciliation.sql` | `gate68_postcheck.sql`, `gate68_lease_schedule_smoke_test_rollback.sql` | `VITE_ENABLE_ONEXA_LEASE_RECONCILIATION` |
| 69 | Gate 68 verified | `gate69_lease_property_financial_report.sql` | `gate69_postcheck.sql`, reporting totals match GL | `VITE_ENABLE_ONEXA_LEASE_PROPERTY_REPORT` |
| 70 | Gate 69 verified | `gate70_lease_receivables_aging.sql` | `gate70_postcheck.sql`, dated aging tie-out | `VITE_ENABLE_ONEXA_LEASE_AGING` |

Enable only the corresponding flag after every prerequisite is checked and a controlled acceptance scenario passes. The top-level posting switch `VITE_ENABLE_ONEXA_POSTING` must already have passed B4 acceptance. Existing accounting rows and legacy `payments`/`invoices` must never be reposted.

**IMPORTANT change in this package:** Gate 68's upcoming SQL definition filters receipt allocations using the *posted native receipt business document and matching journal*. Deploying new repository SQL is not equivalent to updating an already-installed function. If Gate 68 is installed, review its live function definition first; plan a controlled `CREATE OR REPLACE` rollout with rechecks rather than assuming source code changes production.

## 3 — Accounting acceptance (controlled test tenant/data)

- Issue one approved native lease invoice; verify its net amount, VAT, gross, journal reference and legal entity.
- Confirm only the assigned authorized posting user can post; creator self-approval is rejected when policy requires segregation.
- Post a partial native receipt and reconcile invoice outstanding with the AR ledger.
- Gate 68 immutability smoke must FAIL when no posted lease invoice exists; never accept a skipped test as a pass.
- A receipt that is draft, failed, or reversed must **not** reduce the dashboard/snapshot/aging balances. Gate 68 dashboard and Gate 70 anomaly check must follow the same posted-only convention as Gates 69 and 70 report services.
- Use an accounting-date cut-off for Gate 69 and Gate 70: receipts posted after `as_of` must not decrease historical aging; buckets should sum to gross outstanding.
- Verify an inaccessible tenant/property cannot read or alter these records even when an object UUID is known.
- Confirm reversal/idempotency, schedule immutability, tax mapping, and no direct ledger mutation. Inspect returned rows of every postcheck and rollback smoke.
- Test empty property portfolios, multiple legal entities, overlapping due dates, and a partial payment near the month end.

**Cutover rule:** all applicable preflight objects READY, postchecks empty of anomalies, smoke tests pass, zero unapproved high-severity security findings, and finance signs off on AR/GL reconciliation. Keep all flags closed otherwise.

## 4 — CI and evidence

- Run `npm run check:gate68-lease-reconciliation` and `npm run check:gate70-lease-aging`, then `npm run typecheck`, `npm run build`, and `npm run verify`.
- Static Gate checks assert repository contracts; **they do not validate live PostgreSQL function compilation or accounting execution**. Run each SQL against a disposable clone or controlled transaction before production.
- Previous GitHub Actions runs for Gates 68–70 failed. The failure reason could not be reconstructed from the API logs; do not treat these runs as a passing deployment.
- Save the preflight output, postcheck tables, audit events, accounting report reconciliation and GitHub Actions URLs in the change record.

## 5 — Next product work

After confirmed activation of 67–70, complete real ERP process tests (GL, AP, AR, VAT, assets, payroll, jobs and stock), tax/ZATCA integration, a second independently provisioned customer database, multilingual end-to-end UAT, backup/restore drills and commercial provisioning. Gate numbers in the historic roadmap and GitHub implementation series are not interchangeable.
