# ONEXA Gate 67 — Lease invoicing and receipts acceptance

**Customer production: NOT INSTALLED. CODE REVIEW AND SOURCE CHANGES ONLY.** No SQL migration, tenant lease, GL posting, mapping or runtime flags were modified.

## Finance rules

A lease invoice is created from one approved/active tenant lease, due schedule and legal-entity-scoped property. Its GL entry debits AR, credits rental revenue and, when applicable, output VAT. The receipt debits cash/bank and credits AR. Legacy `public.invoices` or `public.payments` must never be re-posted as native ONEXA events.

- A valid invoice/receipt must be `posted`, have a matching native posting row and reference a B4 journal in state `posted` **without** a reversal reference.
- `onexa_lease_receivables_reconciliation` only counts receipts whose business document is posted, whose journal IDs match and whose original journal is **still posted and unreversed**. A reversed receipt retains its audit row but does not reduce effective AR.
- The receipt posting RPC takes a row lock on the invoice to serialize competing collections, checks the invoice's original journal and sums only effective posted unreversed receipts before rejecting overpayment. Reversed historical collections may be replaced by a **new approved source document**, never by re-posting the old one.
- `onexa_lease_accounting_reconciliation` detects reversed/missing journals, source document mismatch, currency mismatch and debit/credit totals inconsistent with the source invoice or receipt.
- Replaying an already-posted invoice/receipt while its original journal is missing or reversed fails with `ONEXA_LEASE_INVOICE_JOURNAL_REVERSED_OR_MISSING` or `ONEXA_LEASE_RECEIPT_JOURNAL_REVERSED_OR_MISSING`, respectively.
- A lease scope already assigned to a tenant, entity, branch or property cannot be silently reassigned by the SECURITY DEFINER scope upsert (error: `ONEXA_LEASE_SCOPE_REASSIGNMENT_FORBIDDEN`), including before posting any invoice. Tenant boundaries remain immutable.
- Posting requires an actual **enabled** Gate 64 approval guard on business documents and authorization of the facilities poster. Client accounting dates default to the browser-local day.

## Real read-only AOA production audit (2026-10-16)

| Component | Connected database |
|---|---|
| `re_properties`, `re_tenant_leases`, `re_lease_schedules` | MISSING |
| `onexa_lease_accounting_scopes`, invoice/receipt posting tables | MISSING |
| `onexa_private.guard_approval_posting()` | MISSING |
| B4 `onexa_journal_headers` | PRESENT |
| `accounts_receivable` | 1120 — active/detail/assets |
| `cash_or_bank` | 1110 — active/detail/assets |
| `output_vat` | 2160 — active/detail/liabilities |
| `rental_revenue` | MISSING (must be approved) |

The sample `gate67_aoa_lease_account_mapping.sql` proposes creating 4510. That is a **proposal**, not an account approved for creation. Check the actual COA, tax treatment and company real estate inventory with Finance before any changes.

## Production rollout order — not executed

1. Verify target customer Supabase project, migration state, **tested restore-capable backup**, change window and Finance approval.
2. Deploy/verify Gate 15 real estate foundations, Gate 40–43 posting engines and Gate 64 approval bridge in the approved order. Confirm the G64 posting trigger is enabled.
3. Review company-specific rental revenue (proposed 4510) and VAT categorization with Finance. Confirm the property, building, unit, tenant, billing schedule, customer and branch in a verified business record.
4. Verify no partial Gate 67 objects already exist. Apply `gate67_lease_invoice_receipt_posting.sql` manually only with explicit authorized approval, then `gate67_aoa_lease_account_mapping.sql` **only if reviewed**, not blindly.
5. Execute `gate67_postcheck.sql` and require zero unmatched invoice/receipt journals, invalid lease scopes, invalid mapping rows and receivable anomalies. Investigate every `journal_reversed_or_missing` and `invoice_journal_reversed_or_missing` finding.
6. Using independent authorized creator/approver/poster identities and a disposable test tenant, run `gate67_lease_accounting_smoke_test_rollback.sql`; require actual pass and final rollback. Confirm debit/credit tax entries, partial collections, late payments, tenant isolation and concurrent allocations.
7. On a disposable database, reverse the invoice/receipt originals and confirm operational reconciliation and retries reflect journal state; verify that effective AR and the general ledger agree and historical receipts remain auditable.
8. Retest Gate 68 schedule dashboard, Gate 69 property report and Gate 70 aging after the new source logic. They must independently exclude reversed journals as well as unposted documents, especially when their SQL queries raw receipt-posting tables.
9. Enable `VITE_ENABLE_ONEXA_LEASE_ACCOUNTING` only after all accounting, security and deployment checks pass.

**Deployment stopper:** accounting/rental mappings missing, real estate prerequisites missing, G64 not active, stale/reversed journals, an inaccessible tenant/property, no backup, unexplained invoices or receipts, or any false reconciled ledger status.

GitHub CI validates source contracts and build output; it does not execute production SQL, guarantee real-world rent collection or certify regulatory VAT treatment.
