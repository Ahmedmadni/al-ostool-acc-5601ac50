# Gate 35 — Sales, Inventory and General Ledger

## Scope

Gate 35 is the first complete accounting-first vertical slice. It connects an approved sales invoice to customer receivables, sales revenue, output VAT, perpetual inventory, cost of goods sold, and the immutable B4 journal in one PostgreSQL transaction.

The package is staged at `supabase/manual-packages/gate35_sales_inventory_posting.sql`. It is intentionally not a migration because the Supabase CLI and an identified development branch are unavailable in this workspace. Production execution remains blocked until B2 and B3 pass.

## Atomic posting flow

1. Resolve the authenticated tenant from `app_metadata.onexa_tenant_id` and the actor from `auth.uid()`.
2. Take a transaction-scoped advisory lock and row-lock the approved sales invoice.
3. Validate branch, customer, document ownership, creator/poster separation, and header-to-line totals.
4. Resolve the five legal-entity account roles: receivables, revenue, output VAT, cost of goods sold, and inventory.
5. Lock inventory balances in deterministic warehouse/item order.
6. Reject missing or insufficient stock and calculate issue cost using moving weighted average.
7. Record one immutable stock issue for every stocked invoice line and reduce quantity/value.
8. Build balanced AR/revenue/VAT and COGS/inventory journal lines with customer, branch, warehouse, and item dimensions.
9. Call the existing `onexa_post_journal` B4 boundary.
10. Store the journal ID, mark the invoice posted, append audit evidence, and commit.

Any failure rolls back inventory, movement records, posting-run evidence, source status, and the journal call together. A safe retry returns the existing journal for an already posted invoice.

## Accounting entry

For an invoice with stocked items:

| Account role | Debit | Credit |
|---|---:|---:|
| Accounts receivable | Gross invoice | — |
| Sales revenue | — | Net sales |
| Output VAT | — | VAT |
| Cost of goods sold | Weighted-average issue cost | — |
| Inventory | — | Weighted-average issue cost |

Service-only lines create no inventory movement or COGS entry.

## Reconciliation and reports

- `onexa_inventory_stock_valuation` exposes quantity, average unit cost, and inventory value by entity, branch, warehouse, item, and currency.
- `onexa_sales_inventory_reconciliation` compares invoice totals, expected stocked lines, actual issues, issue value, posting-run value, and journal linkage.
- `onexa_sales_posting_configuration_gaps` lists missing account-role mappings before posting is enabled.
- The Sales module report page displays posted invoices, reconciliation exceptions, revenue, inventory cost, and gross margin.

## Activation controls

Gate 35 requires B3's tenant-aware server-side permission helper. The posting function revokes `EXECUTE` from `public` and `anon`, grants invocation to `authenticated`, and then rejects callers in the database unless their active workspace role authorizes sales posting. Only after branch testing, account mapping, advisor review, and reconciliation acceptance may both `VITE_ENABLE_ONEXA_POSTING` and `VITE_ENABLE_ONEXA_SALES_POSTING` be enabled.

The next vertical slice is purchase invoice → inventory receipt/asset/expense classification → supplier payable → input VAT → General Ledger.
