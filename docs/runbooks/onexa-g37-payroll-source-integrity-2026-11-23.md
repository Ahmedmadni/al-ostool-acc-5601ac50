# ONEXA Phase 15 — payroll line-level and project attribution integrity (23 November 2026)

**Status:** Source-only safety patch pending isolated CI. Production activation remains **HOLD**; no hosted financial data or payroll amounts have been read or modified.

## Why this fix is required

The Gate37 approved payroll posting could previously:
- Fail to detect a missing employee (the detection query used an inner join, so absent employees disappeared from the cross-tenant mismatch check).
- Treat a cost-ledger entry from a *different project* as a valid payroll line receipt when the tenant and payroll-line source tags happened to match. The GL expense was then attributed to the payroll line's project even though the underlying cost entry belonged elsewhere.
- Accept two incorrect employee cost records if their equal and opposite differences netted to zero in payroll and cost-ledger aggregate totals. That is not a valid employee-level reconciliation.

## Changes

1. Detect both nonexistent and cross-tenant employees with a left-joined lookup before payroll journal creation. Actual payable expense aggregation remains scoped to the authenticated tenant.
2. Require `cost.project_id is not distinct from line.project_id` on the cost receipt in **both** the payroll reconciliation view and the posted payroll aggregation. The null-safe comparison allows genuine unallocated overhead only when both sources are unallocated.
3. Verify **each** verified payroll cost entry equals that same employee's computed employer cost using exact numeric comparison. A pair of offsetting differences raises `ONEXA_PAYROLL_COST_LINE_MISMATCH`, even if the journal's overall debit and credit appear balanced.
4. Extend existing actual Gate37 SQL + real strict B4 synthetic-PostgreSQL tests with wrong-project and offsetting-line corruption attempts. Each exception block rolls back the injected corruption; final test transaction rolls back all created synthetic ledger data.
5. Update the source contract check to pin all three invariants against accidental regression.

## Acceptance boundaries

CI can validate the isolated posting function against the real strict B4 contract, but the synthetic payroll attendance and employer-cost helpers in the test fixture are **not** authentic Gate7/8 implementations. Actual attendance/salary/HR record authorization, IFRS financial accounting decisions, and complete tenant-wide financial reconciliation still require separately restored Staging and approved finance/security E2E tests.

Do not install any source-changing SQL on hosted production based on this source-only merge. Independent backup/restore, Gate7/8 migration compatibility, 11 shared B4 catalog checks and 17 GL integrity categories must be verified before any financial flags are enabled.
