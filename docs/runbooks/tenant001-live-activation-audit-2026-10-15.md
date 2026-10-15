# ONEXA ERP — Tenant 001 live activation audit (2026-10-15)

**Target**: Lovable project `a159a7c0-1de8-4ddb-bab2-f898c5e8ebac` (connected customer PostgreSQL instance).  
**Repository**: `Ahmedmadni/al-ostool-acc-5601ac50` (`main` last inspected `7cbf3b5`).  
**Method**: only SELECT-based inspection. No migrations, writes, flag changes, or tenant configuration changes were performed.  
**Qualification**: A database object existing is *not* a completed deployment: authorization, account mappings, reconciliation, semantic behavior and UAT remain unverified.

## Evidence summary

| Item | Observation |
|---|---|
| Workspace | `tenant-001-al-ostool` exists and is active; plan `enterprise` |
| Legal entity | `AOA`, active; one branch |
| Workspace memberships | 6 |
| Active AOA account-role mappings | 10 |
| Native business documents | 2 |
| Journal headers / manual journals | 0 / 0 |
| Sales posting runs / purchase posting runs | 0 / 0 |
| Customer receipt postings / inventory movements | 0 / 0 |
| Approval workflow / steps | 1 / 3 |
| Approval instances | 0 |
| Capabilities inventory | 14 installed objects, 15 missing objects, out of 29 checks |
| Gate 40–43 prerequisites inventory | 14 present, 6 missing, out of 20 checks |
| Gate 67–70 readiness | 28 of 28 checks BLOCKED because key objects, RLS targets, RPCs and Gate 64 bridge are not installed |

The database contains the core workspace, business-document, journal, sales/purchase/customer receipt and approval (through Gate 63) contracts. The latest version visible in `supabase_migrations.schema_migrations` is `20260918082136`; SQL Editor manual changes may not be in that history. Never decide migration applicability by history alone.

### Confirmed active account role mapping

| Role | Code |
|---|---|
| accounts_payable | 2110 |
| accounts_receivable | 1120 |
| cash_or_bank | 1110 |
| cost_of_goods_sold | 5600 |
| fixed_asset_cost | 1210 |
| input_vat | 1160 |
| inventory | 1130 |
| output_vat | 2160 |
| purchase_expense | 5100 |
| sales_revenue | 4500 |

These represent configured mappings only; they do not prove a successful journal-posting acceptance scenario.

## Hard dependencies blocking downstream Gates

1. **G40:** `onexa_post_supplier_payment(uuid,text)` is missing; B4, G36 objects and AP/bank mapping roles were detected. Run G40 preflight and compare `gate40_supplier_payments.sql` against live schema before any authorized manual rollout; require postcheck and rollback smoke.
2. **G41:** `onexa_treasury_accounts` and `onexa_post_bank_transfer(uuid,text)` are missing. Setup of *two distinct verified detail bank accounts* in the real legal entity/branch must be reviewed by Finance; placeholder accounts are prohibited.
3. **G42:** project cost center and project-cost posting RPC missing. Verify the project, cost center and direct-cost/clearing account mapping. Never double-book source costs recognized in payroll, AP or stock issues.
4. **G43:** the fleet tables and their tenant columns exist, but the trip-cost posting RPC is missing. Use a completed, properly tenant-scoped trip and a reviewed cost mapping.
5. **G64:** approval-posting bridge is missing. Its manual package requires **all** the specified G35/36/39/40/41/42/43 posting signatures and the G63 approval runtime. Do not attempt G64 while 40–43 are absent.
6. **G65:** native inventory receipt/issue posting requires a verified G64.
7. **G14/G15/G66/G67:** operational maintenance (`ops_work_orders`) and real-estate (`re_properties`, `re_lease_schedules`) foundations are absent; activate these from the deferred production migration manifest only after a verified backup, schema-diff check and manual acceptance. G66 also needs G42/G64, and G67 needs G15/G64.
8. **G68–G70:** remain blocked behind verified G67; code merged to GitHub does not execute the SQL automatically.

## Next execution order (approval controlled)

- **Wave A — zero-write readiness**: compare `scripts/production-db/preflight-readonly.sql`, `onexa_erp_capability_inventory_readonly.sql`, `onexa_gate40_43_readonly_preflight.sql` and `lease_gates_67_70_readonly_preflight.sql` output; record a verified backup and a restore test.
- **Wave B — core accounting UAT**: use distinct authorized creator/approver/poster accounts; execute controlled rollback-only smoke for already-installed G35/36/39/58. Confirm no duplicate journals, balanced entries, idempotency and source registry reconciliation.
- **Wave C — treasury/projects/fleet**: carefully apply missing G40, then G41, G42 and G43 packages in dependency order, rechecking each schema/function/mapping and rollback smoke independently.
- **Wave D — approval bridge and inventory**: apply G64 only when all prerequisite posting RPCs are verified, then G65.
- **Wave E — operations and leases**: after the separately verified G14/G15 foundation rollout, apply G66/G67 and only then G68/G69/G70, with actual rental, receipt, cut-off and aging tie-outs.
- **Wave F — finance/product completion**: full AR/AP/bank reconciliation, project profitability, period close, VAT/ZATCA, HR/payroll integration, tenant-2 onboarding, recovery and security tests.

**Stop conditions:** incorrect customer DB, missing backup, partially installed contract, mismatched RPC signature, missing permissions or role mappings, nonzero reconciliation gaps, failed rollback smoke, or a failed cross-tenant negative test. Feature flags must stay disabled until verification and finance signoff.

## CI and merge status — updated 2026-10-15

Initial Interface Readiness runs on Gates 68–70 and early PR #48 attempts failed before any runner steps started (empty `steps`, `runner_id=0`). These failures were **not** evidence of failed application tests. A later runner run executed full checks successfully.

| PR | Code scope | Successful CI run | Merged commit on `main` |
|---|---|---|---|
| #48 | Gate 67–70 lease correctness and read-only activation audit | `38709284922` | `27005e4470a9dbf377ce21185a06564b0a66372c` |
| #49 | Gate 40 supplier payment reversal/AR-AP safeguards | `38712600618` | `2190344904a61f24884523587ff8ecf84f57c07a` |
| #50 | Gate 41 bank transfer and journal reconciliation | `38714504023` | `9361ba626f910c8f9fd0fef26607082363430418` |
| #51 | Gate 42 project cost accrual and mapping safeguards | `38715042301` | `fd73a2b825822cd6766ef774fea7c3fe0a73e2a6` |
| #52 | Gate 43 fleet trip GL reversal and accounting controls | `38715425568` | `ddbf4b2366735dd500a2625111d4e3128843b0d0` |
| #53 | Gate 64 read-only dependency/patch review preflight | `38715887971` | `153ee9d9fe201ea8ea899e0bade602df7375f36e` |

**Do not confuse successfully merged source files with customer database rollout.** The live customer inventory above was SELECT-only: G40–43 posting functions were still missing, the two accounting role mappings for G42 and the two for G43 were absent, and G64 and G65–70 remained blocked. Any deployment requires a fresh read-only inventory, reviewed backups, manually approved SQL, rollback smoke, maker/checker authorization and financial reconciliation. No production SQL migration was applied by these GitHub merges.

## Audit SQL and runbook paths

- `supabase/manual-packages/onexa_erp_capability_inventory_readonly.sql`
- `supabase/manual-packages/onexa_gate40_43_readonly_preflight.sql`
- `supabase/manual-packages/lease_gates_67_70_readonly_preflight.sql`
- `docs/runbooks/onexa-lease-gates-67-70-rollout.md`

This is a live snapshot, not a substitute for re-inspection immediately before changing production.
