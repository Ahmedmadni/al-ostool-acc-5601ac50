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
control account for the legal entity. Al Ostool confirmed account `1110`
(`النقد وما في حكمه`) from the production chart on 2026-09-27. The mapping
package still validates that it is an active detail asset and that the existing
accounts-receivable role is valid before persisting it. Per-bank subledgers and
unapplied customer advances are outside this first slice; the RPC refuses an
unallocated receipt.

Keep `VITE_ENABLE_ONEXA_CUSTOMER_RECEIPT_POSTING` disabled until the manual
package, mapping, postcheck and rollback-only smoke test succeed. Do not apply
the package during the deferred production rollout window.


The rollback smoke test is self-contained across the full Gate 35–39 pipeline.
It creates temporary inventory and a sales invoice, approves and posts the
invoice, creates its fully allocated customer receipt as an authorized maker,
verifies that the maker cannot approve it, approves and posts it as a distinct
authorized operator, checks settlement and retry idempotency, validates
cross-tenant denial, and rolls everything back. Production sales invoices are
never required or modified by the smoke test.
