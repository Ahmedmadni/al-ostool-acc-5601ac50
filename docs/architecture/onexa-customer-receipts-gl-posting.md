# ONEXA Gate 39: customer receipts and receivables

Gate 39 uses a new ONEXA `customer_receipt` business document. The older
`payments` and `invoices` tables in the Al Ostool collections screen remain a
separate legacy workflow. Do not post those records through Gate 39 or count
them again as ONEXA receipts.

The creator enters an amount against a posted ONEXA sales invoice. A different
user approves the document; a user other than the creator posts it. The posting
function locks each invoice, verifies its tenant, entity, branch, customer,
currency, posted journal and remaining receivable, then posts a balanced debit
to `cash_or_bank` and credit to `accounts_receivable` through B4.

Receipt allocations, the posting ledger, the source status and its event are
written atomically with the journal. Retries return the original journal.
`onexa_customer_receivables_reconciliation` reports the remaining invoice
balance; it uses security-invoker and underlying tenant RLS. A receipt may
allocate to multiple invoices through `source_snapshot.invoice_allocations`,
although the first UI supports one invoice per receipt.

The account-role mapping `cash_or_bank` is the selected default cash or bank
control account for the legal entity. Al Ostool's actual account code must be
confirmed by the accountant. The mapping package intentionally fails before
that selection. Per-bank subledgers and unapplied customer advances are outside
this first slice; the RPC refuses an unallocated receipt.

Keep `VITE_ENABLE_ONEXA_CUSTOMER_RECEIPT_POSTING` disabled until the manual
package, mapping, postcheck and rollback-only smoke test succeed. Do not apply
the package during the deferred production rollout window.


The rollback smoke test is self-contained from receipt creation onward. It selects
one posted ONEXA sales invoice with a positive reconciled balance, creates a
temporary receipt as an authorized maker, verifies that the maker cannot approve
it, approves and posts it as a distinct authorized operator, checks allocation
and retry idempotency, validates cross-tenant denial, and rolls everything back.
