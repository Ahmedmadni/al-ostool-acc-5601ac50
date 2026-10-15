# ONEXA — Gate 66 maintenance work-order cost posting acceptance

**Customer Data Plane deployment status: BLOCKED — NOT INSTALLED.**
This development branch changes code only; no customer production SQL, operational work orders, chart of accounts, feature flags or posted journals were modified.

## Purpose and accounting boundary

Gate 66 accrues **new unpaid costs for a completed maintenance work order** to an approved project cost center. Do not rebook materials already issued by inventory (Gate 65), supplier invoices (G36), payroll, fleet, or project costs (G42). Each source external reference remains unique even after a journal reversal.

- Posting is valid only for a completed/accepted `ops_work_orders` record whose company is accessible, an active tenant-scoped work-order scope and project cost center, matching legal entity/branch, cost-source category, a reviewed accounting period, and an authorized poster in the proper approval workflow.
- A reconciled `maintenance_work_order_cost` must reference a **posted, unreversed** B4 journal with matching tenant/entity, source type/ID, currency, debit and credit equal to its source value.
- A reversed or missing original journal yields `journal_reversed_or_missing`. A posted work-order cost cannot return a successful idempotent retry when its journal was reversed: `ONEXA_MAINTENANCE_JOURNAL_REVERSED_OR_MISSING`.
- An existing work-order scope cannot be reassigned to another tenant, legal entity or branch through the SECURITY DEFINER upsert. Cross-scope attempts fail with `ONEXA_MAINTENANCE_SCOPE_REASSIGNMENT_FORBIDDEN`; this prevents a single operational work order being silently transferred between tenants before its costs are posted.
- A scope or project center with another legal entity/branch yields `scope_entity_branch_mismatch`. Journal source/amount inconsistencies yield `journal_source_or_amount_mismatch`.
- Active GL mapping requirements: `maintenance_project_cost` must be a detail WIP asset/cost-of-revenue/expense; four distinct source clearing roles (material, subcontract, labor, other) must each map to an active detail **liability** account. Approval of real account roles is mandatory.
- Gate 64 requires an **enabled approval-posting trigger on business documents** in addition to the function signature. No feature flag should bypass a missing or disabled trigger.

## Verified production dependencies (read-only, 2026-10-15)

| Check | Observation |
|---|---|
| `ops_work_orders` | MISSING |
| `onexa_project_cost_centers` | MISSING |
| `onexa_maintenance_work_order_scopes` | MISSING |
| `onexa_post_maintenance_work_order_cost(uuid,text)` | MISSING |
| Five necessary AOA maintenance account-role mappings | 0 configured |

These are **expected deployment blockers**. Do not guess company IDs, create artificial operational work orders, or replay deferred migration bundles blindly.

## Safe activation sequence

1. Verify the target customer project, production schema inventory and tested restore-capable backup.
2. Manually deploy and verify prerequisite **Gate 14 operations/work orders**, **Gate 42 project centers/cost mappings**, and **Gate 64 accounting approval bridge** in their approved dependency order. Confirm role separation and actual cost-center scope.
3. Obtain real company/project and asset/work-order identifiers from verified operational records and Finance-signed cost/clearing GL mappings. Inspect `gate66_aoa_maintenance_mapping.sql` placeholders; do not use made-up accounts.
4. After separate change-window approval, apply `gate66_maintenance_work_order_costs.sql`. Inspect partial object installations before any DDL; do not blindly rerun migrations.
5. Run `gate66_postcheck.sql`, requiring ready objects, correct RLS/grants/invoker views, an enabled G64 posting trigger, zero mapping gaps and no posted source/journal/scope discrepancies.
6. Run the rollback-only `gate66_maintenance_cost_smoke_test_rollback.sql` with a real completed work-order fixture, an appropriately approved native cost document and distinct authorized users.
7. In a disposable database, reverse the original source journal, verify the maintenance cost reconciliation reports `journal_reversed_or_missing` and the posted-document retry fails closed. Review work order/project cost totals and trial balance to ensure no double booking.
8. After Finance, Project Management and maintenance approval, enable `VITE_ENABLE_ONEXA_MAINTENANCE_COST_POSTING` only as part of a verified release.

GitHub CI is code/build verification only, **not** acceptance of actual operational maintenance accounting.
