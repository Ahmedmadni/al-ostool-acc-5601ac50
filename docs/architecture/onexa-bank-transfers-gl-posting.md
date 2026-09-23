# ONEXA Gate 41: controlled bank transfers

A bank transfer is an approved `bank_transfer` business document owned by Finance.
The creator submits, another user approves, and a finance poster other than the
creator posts it. The source and destination must be two distinct active SAR
treasury accounts within the same tenant, entity and branch. These accounts are
explicitly mapped to active asset detail accounts in the chart of accounts.

The B4 journal debits the destination bank GL account and credits the source
bank GL account by the same amount. The posting row, document status and audit
event are written atomically with that journal. The idempotent retry returns
the existing journal. Views use security-invoker and tenant RLS; authenticated
clients cannot write the treasury mapping or posting table directly.

The older `bank_statements` import remains a separate bank data source. Gate 41
does not manufacture statement rows or claim to reconcile the GL balance with
an imported bank statement. No bank overdraft limit is inferred from a statement.
Only SAR transfers within one entity and branch are included; foreign exchange,
intercompany transfers and bank fees require distinct controlled workflows.

Al Ostool's source and destination GL bank account codes must be confirmed by
an accountant. The manual mapping SQL intentionally fails while placeholders
remain. Keep `VITE_ENABLE_ONEXA_BANK_TRANSFER_POSTING` false until the SQL
package, mapping, read-only postcheck and rollback-only smoke test succeed.
