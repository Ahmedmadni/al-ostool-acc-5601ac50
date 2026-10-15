# Gate 41 — Bank transfer reconciliation and reversal acceptance

**Deployment status:** code change only. Gate 41 tables and RPCs were **not present** in Tenant 001 when read-only inspected on 2026-10-15. No SQL migration has been executed by this change.

## Reconciliation invariants

- A native `bank_transfer` document is considered `reconciled` only if its posting references the same document, tenant and legal entity, and the linked journal is still `posted` with `reversal_journal_id IS NULL`.
- A posted transfer whose original B4 journal has been reversed (or cannot be accessed/found) receives `journal_reversed_or_missing`, **not** `reconciled`. This preserves historical documents while preventing a false operational success.
- A journal whose source type/ID, debit, credit or currency differs from the transfer receives `journal_source_or_amount_mismatch`, not a false reconciled status.
- A transfer whose source or destination account belongs to another legal entity or branch receives `account_scope_mismatch`, even when the account code exists.
- An idempotent repeat call to `onexa_post_bank_transfer` must reject a reversed original journal with `ONEXA_BANK_TRANSFER_JOURNAL_REVERSED_OR_MISSING`. Reusing an old reversed document must never create a second journal.
- The transfer posting RPC requires finance `post`, correct tenant identity, a second human poster, two **different** active detail asset accounts in the same AOA legal entity and branch, the accounting period, and a balanced debit/credit pair.
- Reports use `security_invoker=true`; the document, posting, bank accounts and journal rows must all be visible under verified RLS.
- Default accounting dates in the UI follow the user's local calendar day rather than a UTC ISO date.

## Controlled rollout (not performed by this PR)

1. Verify the exact Customer Data Plane project and current installation state via `onexa_erp_capability_inventory_readonly.sql` and `onexa_gate40_43_readonly_preflight.sql`.
2. Review a current, restorable backup and obtain authorization for all DDL.
3. Confirm **two genuine bank GL detail account codes** for the same tenant/entity/branch; do not use placeholders in `gate41_aoa_treasury_accounts.sql`.
4. Only after independently assessing applied schema, execute `gate41_bank_transfers.sql` under an approved change window.
5. Execute `gate41_postcheck.sql`: require all object/RLS/privilege checks to pass, no scope mismatches or unreconciled posted transfers.
6. Execute the existing rollback-only `gate41_bank_transfer_smoke_test_rollback.sql` with distinct authorized creator/poster identities. Check journal balances and cross-tenant rejection.
7. In a disposable data clone with a reversal-authorized user, reverse one posted transfer journal and confirm the report shows `journal_reversed_or_missing`; the original transfer's idempotent posting retry must fail closed.
8. After reconciliations, financial approval, and audit trail review, and **only then**, consider the `VITE_ENABLE_ONEXA_BANK_TRANSFER_POSTING` flag.

The GitHub CI tests validate source/build contracts, **not** live PostgreSQL operations, bank statements, or permissioned financial acceptance.
