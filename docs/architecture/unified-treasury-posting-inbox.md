# Gate 61 — Unified treasury posting inbox

Gate 61 connects the governed treasury posting services delivered in Gates 39–41 to the central accounting work queue.

## Operational scope

The accounting inbox can now post approved:

- customer receipts through `onexa_post_customer_receipt`;
- supplier payments through `onexa_post_supplier_payment`;
- bank transfers through `onexa_post_bank_transfer`.

The UI calls the existing service boundaries and never writes directly to business-document or journal tables. Each action remains fail-closed behind the global posting switch and its operation-specific runtime switch.

## Runtime activation

Enable an operation only after its SQL package, postcheck, account mapping, and rollback smoke test have passed:

```env
VITE_ENABLE_ONEXA_POSTING="true"
VITE_ENABLE_ONEXA_CUSTOMER_RECEIPT_POSTING="true"
VITE_ENABLE_ONEXA_SUPPLIER_PAYMENT_POSTING="true"
VITE_ENABLE_ONEXA_BANK_TRANSFER_POSTING="true"
```

Disabled operations remain visible in the inbox with the exact Gate needed for activation. Successful posting refreshes the central inbox and the matching receivables, payables, receipt, payment, or transfer view.

## Control boundary

Maker-checker rules remain enforced by the database transition and posting functions. Gate 61 does not relax authorization, tenant scope, accounting-period checks, idempotency, or reconciliation controls.
