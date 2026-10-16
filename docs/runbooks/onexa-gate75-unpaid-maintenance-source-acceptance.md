# Gate 75 — New unpaid maintenance sources, evidence review and G42 document provenance

**Status: SOURCE ONLY. NOT installed on the customer's production database and NOT authorized for rollout.** Gate 75 does **not** create a second general-ledger journal, issue stock, post wages, or approve a payable. It builds a verified source-evidence workflow for only two narrowly scoped classes of genuine newly incurred costs:

| Supported NEW accrual source | Meaning |
|---|---|
| `unbilled_subcontract` | Work by a subcontractor that is incurred, independently documented, and not already invoiced or accrued |
| `other_unpaid_direct` | Direct maintenance service incurred and unpaid, not previously recognized |

**Materials issued from inventory, supplier invoices, payroll, paid wages and previously posted project/maintenance costs are NOT valid new unpaid sources.** They need source-specific, original-ledger attribution and reversal controls instead of a new expense entry. A text reference or staff declaration **cannot prove** that a cost has never been recorded in a separate legacy ledger or supplier system; the finance reviewer must reconcile independent evidence before approving.

## Scope and invariants

`onexa_native_maintenance_unpaid_sources` reserves an uppercase normalized source reference uniquely within each `(tenant_id, legal_entity_id)` and binds it, using a composite FK, to exactly one accepted Gate73 work order and Gate74 project-cost-center scope in the same tenant/entity/branch. It retains creator, source type, evidence reference, amount, reviewer, decision/reason, linked posted document, and audit timestamps. Users cannot directly INSERT/UPDATE/DELETE. An immutable trigger permits only controlled transitions `pending_review → approved/rejected → linked` via SECURITY DEFINER RPCs; rejected and linked sources cannot be reopened or reassigned.

`onexa_register_native_unpaid_maintenance_source` requires active tenant membership, `projects.create`, active OM company scope, accepted work order and matching active cost center/site/branch/legal entity. It rejects already-used references found anywhere in the ONEXA business-document register. It never calls a posting routine.

`onexa_review_native_unpaid_maintenance_source` requires a distinct finance-capable actor with `projects.approve`, `finance.read` and a documented nonempty reason. Creator, work-order creator and work-order completer cannot review. It rechecks the reference collision before approval. Approval is **authorization to prepare a G42 document**, not authorization to post it.

`onexa_guard_native_claim_business_document` is a **server-side business-document INSERT/UPDATE guard**. Any `maintenance_source_claim_id` must reference an approved Gate75 claim with the same tenant/entity/branch, reference, gross amount, G42 `project_cost` type, native origin, SAR currency, `unpaid_direct_cost` snapshot kind and project-cost-center ID. Once an active business document has a claim marker, its claim ID cannot be changed/removed. A partial unique index on the existing `onexa_business_documents` table prevents two active project-cost documents for one claim. Gate42's standard approval, period validation, account mappings and G64 posting guards continue to govern journal creation.

`src/lib/maintenance/native-unpaid-source-service.ts` provides typed gated RPC helpers plus a **draft-only** G42 project-cost preparer. The preparer reads an approved source and active cost center under normal RLS, then calls the standard `createBusinessDocument` method with the Gate75 claim ID in the snapshot. **It does not submit, approve, post or silently create an additional journal.** Actual posting and independent cost attribution require the existing G42 → G64 → G74 workflow. Only afterward can `onexa_link_native_unpaid_maintenance_source` close the provenance loop by matching source reference, amount, origin, revision, journal identity and original unreversed posted state. The Gate74 work-order attribution must already match the same document, center and order. Attempts to relink another document fail.

`onexa_native_maintenance_source_reconciliation` is a security-invoker view. It preserves approved/linked history but flags a reversed GL source, changed document, posting mismatch or wrong work-order attribution as an anomaly. The source evidence is not deleted or re-accrued. A read-only UI review panel is gated behind all native company/operations, G42 and Gate75 flags. No finance approval or posting buttons appear in this panel.

## Verified production dependencies as of 2026-10-16 (read-only)

B4 journal headers are present; **G42 project cost centers/posting ledger, G71 company scope, G72 native sites, G73 native work orders, and G74 cost attribution remain missing on production**. Gate75 is also code-only. Only one live tenant is present, which is **not** a multi-tenant isolation test. No production SQL, GL posting, test tenant, role, account mapping or feature flag has been applied.

## Staging / approval checklist (no automatic execution)

1. Verify correct customer project, a restore-capable backup and two independently provisioned **disposable staging test tenants**, with different entity/branch/role/OM scopes and real test-only work orders, cost centers and documents.
2. Independently deploy, postcheck and accept G42, G64, G71, G72, G73 and G74 in the disposable clone. Never run unsafe legacy G13–15 or Gate66. Confirm Gate65 SQL delimiter fix #66 before any approved stock flow.
3. Inspect existing business-document indexes and uniqueness conflict risks. **An index on `onexa_business_documents` is added**, so review the lock budget and deploy in a controlled maintenance window only.
4. Apply `gate75_native_maintenance_unpaid_source_review.sql` only to the clone, then execute `gate75_postcheck.sql`. Require valid tenant/entity/branch composite FKs, active RLS, invoker view, both enabled guard triggers, denied anonymous privileges and denied authenticated direct DML. Anomalies must be reconciled.
5. From tenant A, try registering an unpaid subcontract cost for tenant B's accepted work-order UUID, foreign cost center, branch or company. Try reviewing from the source creator or work-order completer. All must fail without creating claims/documents. Repeat in the opposite direction. Test uppercase normalization, duplicate reference and concurrent reservation.
6. Reject `inventory_issued`, `payroll_posted`, `supplier_invoice_posted`, and rebooked prior G42/G66 source types. Prove a reference already on a sales/purchase/cost document cannot be registered. **Separately** review supplier invoice/payroll/inventory evidence because not all systems may share one reference key.
7. Approve one genuine new source with an independent reviewer, create its native G42 DRAFT, then attempt a second active document with the same claim ID (must fail). Attempt to change or erase source snapshot ID, currency, amount, company, center or reference (must fail).
8. Submit/approve/post the document via normal G42 + G64, and attribute it to the accepted order with Gate74 using independently authorized actors. Confirm exactly **one new B4 journal** from Gate42 and **zero additional B4 journals** from Gate75 or Gate74. Reopen the claim via `onexa_link_native_unpaid_maintenance_source` and require precise journal/amount/revision consistency. Retrying the same link must be idempotent.
9. Reverse the original G42 journal through the approved reversal path; claim history persists but `current_reconciliation_status` reports `original_journal_reversed_or_missing`. Financial dashboards must not count the reversed original as a currently reconciled expense.
10. Leave `VITE_ENABLE_ONEXA_NATIVE_UNPAID_SOURCES` blank on production until operations, finance, security and database administrators sign off. All key SQL packages are source-only until runtime integration and cross-tenant negative tests pass.

**Open items:** material issue/payroll/invoice attribution should be built from authoritative posted source tables and compensating entries, not manual re-accrual. Gate75 does not prove third-party evidence is unpaid without an independent finance review; it is a controlled claim/provenance foundation.

**GitHub CI source assertions are not proof of PostgreSQL runtime execution or financial UAT.**
