# Gate 43 — Fleet trip cost posting acceptance

**Status:** code review and hardening only; **no production SQL rollout**. Tenant 001 does not currently have the Gate 43 posting RPC installed.

## Business and accounting meaning

The source must be a **completed tenant-scoped fleet trip** and a *new unpaid trip-specific cost* that is not already recognized through fuel issues, maintenance, payroll, purchase invoices or project costs. Its GL effect is an accrued payable/clearing liability and a reviewed logistics/project expense or WIP account. The original source reference remains unique, including after reversing the original journal.

## GL and reconciliation controls

- A posted `fleet_trip_cost` is reconciled only when the posting row belongs to the source document's tenant and entity, its B4 journal exists with `state='posted'` and no reversal, source document type/ID match, currency and both debit/credit totals equal the source cost, and trip scope agrees with legal entity and branch.
- An original journal that is now reversed/missing is `journal_reversed_or_missing`, not `reconciled`. Repeating an already-posted request against that original journal throws `ONEXA_FLEET_TRIP_JOURNAL_REVERSED_OR_MISSING`, not a false success.
- A wrong trip-to-entity/branch match is `trip_scope_mismatch`; a wrong journal source or amount is `journal_source_or_amount_mismatch`.
- The account mapping must pair an active detail asset/expense/cost-of-revenue account (`logistics_or_project_cost`) with a distinct active detail liabilities account (`cash_ap_or_clearing`, for this currently **unpaid** accrual). An existing paid bank charge must not be imported here.
- The posting RPC must check tenant, relevant logistics permission, separate creator/poster, completed trip and matching vehicle, currency/amount and open period. `security_invoker` reconciliation reads must respect tenant RLS.

## Live read-only fact (2026-10-15)

The connected AOA Tenant 001 DB has neither `logistics_or_project_cost` nor `cash_ap_or_clearing` account role mapping. Their GL codes **must be approved by Finance**, never chosen from an assumed numbering pattern. `fleet_trips` and `fleet_vehicles` were present with tenant IDs; the Gate 43 posting function and tables were not installed.

## Controlled deployment acceptance

1. Verify the correct customer database reference, a restorable backup and current migration/schema inventory.
2. Review `onexa_gate40_43_readonly_preflight.sql`, `gate43_aoa_fleet_trip_mapping.sql` and an actually completed trip and vehicle. Replace every `REPLACE_...` placeholder with confirmed production IDs/codes **only after** finance approval.
3. Execute `gate43_fleet_trip_costs.sql` manually in an approved change window only when the corresponding objects are verified missing and dependencies are present.
4. Run `gate43_postcheck.sql` and confirm all objects, RLS, function privileges, role mappings, completed trip-scope integrity and GL reconciliation are satisfactory.
5. Use distinct authorized users to run the rollback-only `gate43_fleet_trip_smoke_test_rollback.sql`, requiring an actual pass rather than a skipped test.
6. In a disposable DB, simulate an original journal reversal and assert `journal_reversed_or_missing` and a failed idempotent retry. Confirm GL balances, source lineage and tenant isolation.
7. Only after sign-off enable `VITE_ENABLE_ONEXA_FLEET_TRIP_COST_POSTING`; the top-level posting gate must also be independently approved.

**Reminder:** GitHub CI checks application code. It does not execute customer migrations, configure accounting codes or prove posting a real transaction.
