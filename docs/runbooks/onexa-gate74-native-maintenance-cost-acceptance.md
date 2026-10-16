# ONEXA Gate 74 — Attributing posted project costs to native maintenance work orders

**Status: SOURCE ONLY — NOT INSTALLED ON THE PRODUCTION CUSTOMER DATA PLANE.** This is **not** a new GL cost posting engine. It links existing *posted and unreversed* Gate 42 project-cost journals to accepted Gate 73 tenant-native maintenance orders without creating additional accounting entries.

## Accounting treatment and duplication safety

A real maintenance cost already posted through an approved project-cost source must not be booked a second time via another journal. Gate 74 only records an *attribution* between an accepted work order, its fixed tenant/entity/branch project cost center, and a posted project cost document. The original Gate 42 document and B4 journal remain the sole source of GL cost. **Do not rebook** paid/posted purchases, inventory issues, payroll, fleet, legacy Gate 66 maintenance costs or previously accrued Gate 42 costs.

For the first implementation, **only one complete posted Gate 42 project-cost document may be allocated to one work order**, with no splitting or fractional allocations. The unique `(tenant_id,document_id)` constraint prevents use of the same document twice. Matching amount, revision, original journal, currency, debit, credit and document origin must be verified before attribution. The source type must be `project_cost`, document status `posted`, journal status `posted` with **no reversal link**. Reversed or mismatched source journals never contribute to current reconciled cost totals, including after an attribution was previously recorded. Reversal does not delete the historical attribution record.

Gate 74 adds:
- `onexa_native_maintenance_cost_scopes` — one immutable project cost center for each accepted native work order, composite-scoped tenant/entity/branch/work-order and center FKs
- `onexa_native_maintenance_cost_attributions` — immutable evidence of one existing posted project cost per source document, with composite FKs to the native scope and Gate 42 posted source
- `onexa_save_native_maintenance_cost_scope(uuid,uuid)` — requires active current-tenant membership, `projects.create`, active OM alias, accepted work order, active matching cost center and site/branch/legal entity. Repeated calls with the same center are idempotent; changes are refused
- `onexa_attribute_posted_project_cost(uuid,uuid)` — requires active current-tenant membership, `projects.approve`, `finance.read`, active OM alias, accepted work order, independent actor (neither work-order creator/completer nor original G42 poster), and currently posted/unreversed matching B4 journal. It locks records before inserting and checks for existing attribution of the same document; no `onexa_post_journal` calls
- `onexa_native_maintenance_cost_reconciliation` and `onexa_native_maintenance_work_order_cost_totals` — security-invoker read-only reporting. Counts and totals include only currently reconciled journal-backed attributions, with anomalies separate

Direct authenticated writes to mapping tables are denied; immutable SQL triggers block update/delete even from service-role DML. Reporting and base-table SELECT honor ONEXA tenant claim and role-based RLS. The existing **Gate 66 legacy cost posting package is incompatible with native Gate 73**. The original `gate66_maintenance_work_order_costs.sql` now fails at preflight when `onexa_tenants` exists, preventing a tenant-aware deployment from installing the unsafe legacy posting route. It is not invoked and must remain disabled in this workflow.

## Connected database findings (2026-10-16, SELECT only)

| Component | Status |
|---|---|
| ONEXA B4 journal headers | Installed |
| Gate 42 project cost centers and posting ledger | Missing |
| Gate 71 company aliases | Missing |
| Gate 72 native sites/assets | Missing |
| Gate 73 native work orders | Missing |
| Gate 74 attribution tables and views | Missing by definition (new code) |

Only one ONEXA tenant has been observed in production. **This is not a multi-tenant acceptance test.** No DDL, GL journal posting, production data modification or feature flag change has been made as part of Gate 74 development.

## Safe staging acceptance sequence

1. Verify the correct customer instance and a **tested restorable backup**, then use a disposable clone with two *independent test tenants*. Record approved engineering, finance and operations reviewers.
2. Deploy and test Gate71 → Gate72 (including PR #63 SQL quote correction) → Gate73; separately install Gate42 project-cost engine and its real accounting approvals/mappings and Gate64 approval-posting controls before creating posted Gate42 test documents. Do not install legacy Gate13–15 or run Gate66.
3. Confirm Gate74 has zero partial objects. Review unique index creation on existing Gate42 and Gate73 tables and lock duration. Install `gate74_native_maintenance_posted_cost_attribution.sql` **only on the clone**.
4. Run `gate74_postcheck.sql`. Require validated tenant/entity/branch scope FK and project-source FK, active RLS, invoker reporting views, append-only triggers, negative anon privileges and negative authenticated DML. Create one approved project cost via normal G42 workflow; attribute to a different actor's accepted work order at the same center and scope.
5. Verify source document amount/revision/journal equal the attribution; the GL journal count and GL total **do not change** before versus after attribution. Repeating an identical attribution is idempotent, but trying to allocate its source document to a different work order, center, tenant or company must fail. Test different tenant users with known foreign UUIDs; no cross-tenant access.
6. Reverse the G42 source via the approved B4 reversal process, then confirm attribution history persists but the reconciliation status changes to `journal_reversed_or_missing` and the current reconciled cost total excludes that amount. Further attribution attempts against the reversed original must fail.
7. Test inactive work order/site/company scope/branch/legal entity/project center, rejected or unaccepted work order, wrong project cost center, inactive membership, insufficient finance or project role, same creator/poster, mismatched document amount/source/currency, and direct update/delete attempts. Require all to fail without phantom allocations.
8. Only after explicit finance/UAT sign-off and a maintenance downtime/backup plan should **production installation be considered**. Keep the native attribution UI flag blank until all requirements are verified.

**STOP:** any new GL journal generated by cost attribution, duplicate cost, cross-tenant access, incorrectly accepted reversal, missing approval actor separation, partial schema, missing postcheck, or untested restore.

## Work remaining after Gate 74

This stage **does not recognize new unpaid maintenance costs** or automate materials, payroll or subcontractor costs. It does not replace Gates 42, 64, 65 or the original B4 engine. Next milestones: native inventory/material and contractor cost-source integration, branch/project accounting acceptance, ledger reversal tests and transaction-backed end-to-end UAT. Static CI checks alone are not evidence of running PostgreSQL procedures successfully.
