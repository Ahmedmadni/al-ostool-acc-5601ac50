# ONEXA Phase 7 — Shared B4 ledger integrity and hosted schema compatibility (2026-11-18)

## Verified live catalog facts — SELECT only, no customer financial rows

1. The installed `public.onexa_journal_headers` constraint `onexa_journal_headers_source_document_type_check` allows exactly 17 document source types, including `journal_reversal`, but **omits `manual_journal`**. Therefore Gate58, even with a valid posted manual document and real B4 integration, cannot reach the hosted general ledger: its `manual_journal` source type violates the installed header CHECK.
2. The installed `onexa_journal_headers_check` is `CHECK (abs(total_debit - total_credit) <= 0.005)`. The source of `onexa_private.post_journal` also accepts differences up to `0.005`, and its two totals are declared `numeric(20,4)` before checking balance.
3. The installed shared B4 publisher treats missing `debit` or `credit` values as zero and can round monetary inputs on insertion. The Gate58 create RPC is stricter, but sales, purchases, payroll, supplier payments, assets, fleet, and other B4 sources bypass that creation path.

These are **confirmed definition-level findings**. The synthetic SQL pipeline reproduces each legacy behavior without using real customer data.

## Changes prepared, not deployed

- `gate58_b4_gl_source_type_REVIEW_ONLY.sql`: exact observed-definition preflight, then adds a `manual_journal` option while retaining all previously permitted source types. The replacement CHECK is added as `NOT VALID`, validated, and atomically swapped in a maintenance transaction. It performs no journal inserts or edits.
- `gate58_b4_gl_exact_balance_REVIEW_ONLY.sql`: exact old-constraint preflight; **stops if any historical header totals differ**. It then proposes an exact-equality `total_debit = total_credit` constraint using a staged/validated replacement. No auto-balancing or rewriting of historic ledger entries is permitted.
- `gate58_b4_strict_monetary_REVIEW_ONLY.sql`: checksum-gated replacement for the real `onexa_private.post_journal` body observed at MD5 `5ac58a780bbed49e8ba31b6f46c39f48`. Proposed rules reject partial/missing/non-numeric line amounts, reject fractional SAR halalas, prevent silent numeric(20,4) rounding, check exact total equality and refuse empty source references or null revision/approval. It preserves the existing fiscal-period gate, posting idempotency registry, audit and ledger insertion mechanics and privileges.
- **Do not apply to hosted production** without a dedicated independent Staging project, proved backup restore, legal-entity authorization checks, accountant sign-off on rounding/currency policy, security/finance review, and a planned DDL lock window.

## Executable tests

The new CI workflow `onexa-b4-shared-ledger-integrity.yml` is completely separate from the prior Gate58/B4 smoke and runs a clean PostgreSQL 16 `onexa_gate_test`. It uses the **actual installed B4 function source snapshot** with synthetic parent tables, two fake tenants, fake memberships and open fiscal periods. It then:

1. Recreates both hosted header CHECK constraints exactly in a disposable database.
2. Demonstrates the legacy manual source rejection and the original shared-B4 tolerance, silent rounding and omitted-line-amount acceptance, with every financial test transaction rolled back.
3. Dry-runs the review-only source-type and header-balance constraint patches against the disposable exact precondition.
4. Installs the exact strict-B4 candidate function body, cross-checked against the review-only patch by source parity tests.
5. Exercises ten recognized document-source **types** via actual checked B4 RPCs (including sales, purchases, payroll, supplier payments, assets, projects, fleets, bank transfers and manual journals), verifies storage and idempotency, and rejects sub-half-cent imbalances, >4 decimal storage, SAR >2 decimal values, null/omitted/string amounts, null approval or revision, and blank source identity. Tests for KWD demonstrate three decimal storage remains supported, pending an approved currency-specific policy.
6. Exercises the Gate58 real post/reversal smoke after the staged schema and monetary corrections; all synthetic financial rows are rolled back.

**Important limit:** Ten source-type API contract examples are NOT ten full module-level live acceptance tests. Modules' actual posted payloads and privileges may differ, so the proposed shared B4 patch remains unapproved pending restored Staging with every financial integration.

## Other unresolved release risks

- The global B4 idempotency registry keys on source type/id/revision. A repeated call whose payload changed without incrementing the source revision could be treated as a prior successful post; a separate idempotency payload-integrity audit is required.
- Confirm the actual header/line precision, tenant roles, account details and ledger reversal constraints on Staging. This CI's parent tables are intentionally synthetic, not a copy of production.
- Review historical imbalanced GL headers only with an approved **read-only** finance report; the schema patch must refuse to proceed until issues are resolved by an explicitly approved accounting action, not hidden by code.
- Review finance currency scales and cases that legitimately require rounding at document/source calculation. B4 must not silently correct them.
- No independent restored ONEXA Staging or approved production rollout has been verified. Previous Gate58 version patches, ACL grant review, feature flags, and hosted UI save/readback/print acceptance remain pending.

**Decision: HOLD.** A GitHub merge and Lovable source sync do not apply any B4, table-constraint, permission or other SQL migration to the connected customer's live database.
