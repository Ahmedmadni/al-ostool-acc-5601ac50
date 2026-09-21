# Gate 36 — Procurement, Inventory and General Ledger

## Scope

Gate 36 connects an approved supplier invoice to accounts payable, recoverable input VAT, inventory receipts, purchase expenses, capitalized fixed-asset cost and the immutable B4 journal in one PostgreSQL transaction.

Every invoice line carries an explicit accounting classification:

- `inventory`: requires an item and warehouse, increases quantity and value, and recalculates moving weighted-average cost.
- `purchase_expense`: posts the net line amount to the configured purchase-expense account.
- `fixed_asset_cost`: capitalizes the net line amount to the fixed-asset cost account; asset-register creation remains owned by the Fixed Assets module.

## Atomic posting flow

1. Resolve tenant and actor from the authenticated session.
2. Lock the approved purchase invoice and enforce creator/poster separation.
3. Validate vendor, branch, totals and every line classification.
4. Resolve AP, input VAT, inventory, purchase-expense and fixed-asset account roles.
5. Lock inventory balances in deterministic warehouse/item order and record receipts at net line cost.
6. Build one balanced AP/VAT/classification journal and call the existing `onexa_post_journal` boundary.
7. Link inventory movements to the journal, store the posting run and mark the source invoice posted.

A failure rolls back the document status, stock, movements, posting evidence and journal call together. A safe retry returns the existing journal for an invoice that is already posted.

## Accounting entry

| Account role | Debit | Credit |
|---|---:|---:|
| Inventory / purchase expense / fixed-asset cost | Net classified lines | — |
| Input VAT | Recoverable tax | — |
| Accounts payable | — | Gross supplier invoice |

## Controls and activation

- Direct client writes to posting-run and inventory tables remain revoked.
- Tenant RLS and procurement read permission protect reports.
- Posting requires the server-side `procurement.post` authorization check.
- Views use `security_invoker = true`.
- `VITE_ENABLE_ONEXA_PROCUREMENT_POSTING` remains false until the SQL package, AOA mapping, postcheck and rollback smoke test pass.
