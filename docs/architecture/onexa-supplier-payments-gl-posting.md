# ONEXA Gate 40: supplier payments and payables

Gate 40 uses a new ONEXA `supplier_payment` business document. The older
`payments` and `invoices` tables in the Al Ostool vendor payments screen remain a
separate legacy workflow. Do not post those records through Gate 40 or count
them again as ONEXA payments.

The creator enters an amount against a posted ONEXA procurement invoice. A different
user approves the document; a user other than the creator posts it. The posting
function locks each invoice, verifies its tenant, entity, branch, vendor,
currency, posted journal and remaining payable, then posts a balanced debit
to `accounts_payable` and credit to `cash_or_bank` through B4.

Payment allocations, the posting ledger, the source status and its event are
written atomically with the journal. Retries return the original journal.
`onexa_supplier_payables_reconciliation` reports the remaining invoice
balance; it uses security-invoker and underlying tenant RLS. A payment may
allocate to multiple invoices through `source_snapshot.invoice_allocations`,
although the first UI supports one invoice per payment.

The account-role mapping `cash_or_bank` is the selected default cash or bank
control account for the legal entity. Al Ostool's actual account code must be
confirmed by the accountant. The mapping check requires the same confirmed account used by Gate 39;
it never changes the existing account mapping. Per-bank subledgers and unapplied vendor advances are outside
this first slice; the RPC refuses an unallocated payment.

Keep `VITE_ENABLE_ONEXA_SUPPLIER_PAYMENT_POSTING` disabled until the manual
package, mapping, postcheck and rollback-only smoke test succeed. Do not apply
the package during the deferred production rollout window.
