# ONEXA — Gate 65 inventory GL and physical stock acceptance

**Status: CODE ONLY. Gate 65 is NOT installed on the Customer Data Plane.** No live stock movements, GL reversals, account mutations or SQL migrations were executed.

## Critical inventory accounting boundary

A stock movement and the corresponding GL journal are one economic event. A bare journal reversal does **not** restore physical units, original cost layers or the weighted-average valuation. After Gate 65 installation:

- The `onexa_guard_inventory_journal_reversal` trigger blocks setting the original journal to `reversed` when it belongs to a posted Gate 65 inventory run. Error: `ONEXA_INVENTORY_STOCK_COMPENSATION_REQUIRED`. The enclosing B4 reversal transaction should roll back atomically.
- Reversing inventory requires a separately reviewed **paired stock-and-GL compensation workflow**. Do not disable the trigger or manually edit stock balances or journal states as a workaround. Document the required reversal, trace its cost, seek Finance/Inventory approval, and implement a dedicated controlled compensation flow first.
- `onexa_inventory_document_reconciliation` confirms the original B4 journal is still `posted`, unreversed and in the source's tenant/entity. Journal document type/ID, currency and debit/credit totals must equal the posted inventory value.
- Every movement must reference the same posted GL journal. Missing/multiple journal IDs or IDs differing from the posting-run journal produce `movement_journal_mismatch`.
- Retry of an already-posted stock document returns its journal only if the journal still exists in the posted, unreversed state. Legacy inconsistencies fail closed rather than pretending to succeed.
- Warehouse and item identifiers, document lines and valuations must remain tenant- and entity-scoped, and inventory operations require the Gate 64 approval-posting bridge **with an enabled posting guard trigger**, not just a dormant function.
- The inventory ledger's active detail asset mapping (`inventory`) must be paired with an active detail GRNI liability (`goods_received_not_invoiced`) for receipts, or an active detail WIP/cost/expense account (`project_cost_cogs_or_expense`) for issues. The effective mapping is validated at posting time.

## Live read-only findings (2026-10-15)

- Existing Tenant 001 `onexa_inventory_balances`, `onexa_inventory_movements`, `onexa_journal_headers` and business-document foundations are installed.
- `onexa_inventory_posting_runs` is **MISSING**, so this Gate has not been installed in the live customer database.
- AOA account-role `inventory` maps to active asset/detail account **1130**, but `goods_received_not_invoiced` and `project_cost_cogs_or_expense` role mappings are **MISSING**.
- `gate65_aoa_inventory_mapping.sql` proposes accounts 2120 and 5700 with GL inserts. Those account creations and classifications need accountant confirmation; **do not auto-run** the mapping package or assume the account numbers are valid.

## Authorized manual rollout path

1. Confirm the exact ONEXA Customer Data Plane, a tested restorable backup, maintenance window and finance/warehouse consent.
2. Run the read-only core inventory/GL object inventory. Inspect the **current** installed gates. G40–43 must be applied and verified before G64; G64's guard **and enabled trigger** must be verified before G65.
3. Obtain accounting approval of actual inventory/GRNI/issue-cost account mapping, underlying parent accounts and the direct-calc weighted-average stock policy.
4. Review existing physical movement/stock balances and reconcile the starting opening inventory. Confirm no legacy transaction bypass or unposted inventory balance remains.
5. Only after approval, apply `gate65_inventory_gl_posting.sql` (and independently approved `gate65_aoa_inventory_mapping.sql`, if appropriate) in the required controlled order after checking for already installed objects.
6. Run `gate65_postcheck.sql`. Require all objects/trigger/RLS/permissions to be ready, all category-valid GL mappings installed, and **zero** journal, stock-movement or inventory-value mismatch exceptions.
7. Use an approved native receipt and issue with distinct creator/approver/poster identities to run `gate65_inventory_smoke_test_rollback.sql`. Its expected success is followed by a `rollback;`; no live inventory should persist. Separately validate cross-tenant attempts and stock insufficient-quantity constraints.
8. In a **disposable cloned database**, verify a finance-authorized generic journal reversal against a posted stock document fails with `ONEXA_INVENTORY_STOCK_COMPENSATION_REQUIRED` and no partial financial or inventory changes survive.
9. Only after reconciliation, proof of maker/checker controls, and Finance + warehouse sign-off may `VITE_ENABLE_ONEXA_INVENTORY_POSTING` be enabled.

**Stop conditions:** unapproved mappings, unexpected journal reversal capability, missing/disabled Gate64 trigger, mismatched GL/journal IDs, stock valuation drift, unsupported direct legacy writes, missing backup or any tenant boundary weakness.

GitHub CI verifies source code only, **not real physical inventory acceptance**.
