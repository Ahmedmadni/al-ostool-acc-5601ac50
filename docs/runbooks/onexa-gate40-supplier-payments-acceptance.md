# Gate 40 — Supplier payments accounting acceptance

**Deployment status: CODE ONLY — NOT DEPLOYED to the customer database.**
Target ONEXA tenant: `tenant-001-al-ostool`, legal entity: `AOA`.
The live customer database was read-only inspected on 2026-10-15; Gate 40 functions/tables had not been installed.

## Critical accounting contract

- A purchase invoice is payable only if its business document, purchase posting and **original journal** agree, and the original journal remains `posted` (not `reversed`).
- An allocation reduces AP only when its payment posting belongs to the **same tenant, legal entity and vendor** as its source invoice, its source business document is `posted`, its journal IDs match, and that journal is still `posted` and not reversed.
- If a payment journal has been reversed, the allocation remains in historical records but must **not** reduce outstanding AP. Posting the **same payment** again is rejected. A new controlled document and review are necessary to effect a new payment.
- The reconciliation view is `security_invoker=true`; its underlying posting, document and journal tables must be readable through tenant-scoped RLS.
- The payment function serializes competing allocations with invoice `FOR UPDATE`, verifies the original invoice journal and rejects overpayment; never overwrite legacy `public.payments`.
- Configuration readiness requires a live, active **detail** AP liability account and active **detail** bank/cash asset account. Existence of an account-role mapping alone is not sufficient.

## Read-only facts observed in the connected customer database

- `onexa_post_journal`, `onexa_purchase_posting_runs`, `onexa_business_documents` and corresponding foundational tables exist.
- `onexa_post_supplier_payment(uuid,text)` was **missing** as of the audit.
- For legal entity AOA: `accounts_payable = 2110` (active/detail/liabilities) and `cash_or_bank = 1110` (active/detail/assets) both passed classification checks.
- The connected database already contained **no posted native ONEXA journal entries**. Therefore no complete native supplier payment reconciliation could be demonstrated.
- `onexa_private.reverse_journal` changes the original journal state to `reversed`, with a linked reversal journal ID. The Gate 40 SQL must respect this **actual** B4 state machine.
- `onexa_journal_headers` and `onexa_business_documents` have tenant RLS read policies; purchase posting runs require procurement read access.

## Controlled deployment sequence

1. Confirm the Customer Data Plane project reference, current schema, production change window and a **tested** restore-capable backup.
2. Run `onexa_gate40_43_readonly_preflight.sql` and compare `gate40_supplier_payments.sql` with the actual installed functions/tables before **any** DDL.
3. Run `gate40_supplier_payments.sql` **manually only after authorization**. Do not re-run blindly if some objects are present; production DDL needs a reviewed reconciliation plan.
4. Run `gate40_postcheck.sql`. All expected objects/RLS/invoker-view permissions must be `READY`; `payment_allocation_source_integrity` must report zero invalid rows; check the maker/checker readiness result.
5. Run `gate40_aoa_account_mapping.sql` to independently confirm mapping. Review the bank account used for actual payment settlements, and do not use a fictitious mapping.
6. Create an approved purchase invoice and an approved supplier payment with distinct creator and poster; run `gate40_payment_smoke_test_rollback.sql` and require the explicit `passed` notice. Smoke SQL is intended to roll back; do not use live paid invoices or force real-world bank movements.
7. In a **disposable data copy**, verify the reversal path separately: reverse the payment's original journal, then confirm that the AP view **restores** the amount outstanding; the same payment's posting retry fails with `ONEXA_PAYMENT_POSTED_JOURNAL_REVERSED_OR_MISSING`. Reverse the purchase invoice's journal and verify `invoice_journal_reversed_or_missing` status and rejection of further payments.
8. Reconcile AP control account `2110`, cash/bank `1110`, purchase posting rows, supplier allocation totals and the source audit trail. Check tenant isolation, permissions, concurrency, partial payments and idempotency.
9. Enable `VITE_ENABLE_ONEXA_SUPPLIER_PAYMENT_POSTING=true` **only after** successful database postcheck, full tests and Finance approval. Keep `VITE_ENABLE_ONEXA_POSTING` subject to separate B4 approval.

**Stop conditions:** unexpected schema changes, invalid account mapping, missing backup, creator/poster segregation failure, unreconciled or orphan payment allocations, reversed-journal discrepancy, failed smoke, production SQL that has not been reviewed, or an unverified tenant boundary.

## Implementation files

- `supabase/manual-packages/gate40_supplier_payments.sql`
- `supabase/manual-packages/gate40_postcheck.sql`
- `supabase/manual-packages/gate40_aoa_account_mapping.sql`
- `supabase/manual-packages/gate40_payment_smoke_test_rollback.sql`
- `scripts/check-gate40-supplier-payments.mjs`

GitHub CI validates source/build readiness only; it does **not** indicate a production migration was performed.
