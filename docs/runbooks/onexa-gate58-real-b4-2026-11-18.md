# ONEXA — Phase 6: installed B4 general-ledger source acceptance (2026-11-18)

## Source inspected — NOT financial data

Read-only `pg_get_functiondef` inspection of the connected ONEXA project's installed code traced the dispatch chain:

`public.onexa_post_journal` → `public.onexa_post_journal_unchecked` → `onexa_private.post_journal`

`public.onexa_reverse_journal` → `public.onexa_reverse_journal_unchecked` → `onexa_private.reverse_journal` → `onexa_private.post_journal`.

Installed function hashes (2026-11-18, full `pg_get_functiondef`):
- `public.onexa_post_journal`: `0f8adeaf5c85cd470f1c1a29b6545376`
- `public.onexa_reverse_journal`: `ac77042a26c0c954a7f26402a583f52e`
- `onexa_private.post_journal`: `5ac58a780bbed49e8ba31b6f46c39f48`
- `onexa_private.reverse_journal`: `f51a890027057a0e838c13cbfd6ddb61`

The installed private publisher checks for an OPEN legal-entity fiscal period that contains the accounting date and uses an idempotency registry, guarded by an advisory lock. The private reversal invokes this publisher in the selected reversal period; it does not directly bypass the fiscal period restriction.

**Material accounting risk:** the shared `onexa_private.post_journal` still tolerates up to `0.005` difference between the two journal totals and accumulates into `numeric(20,4)`. Gate 58 source checks exact equality and SAR halalas, but other source modules may bypass those Gate58-specific controls. Remediating the SHARED B4 publisher needs impact tests on sales, purchases, HR, assets, payments, project/fleet costs, and finance approval. No shared B4 production change was attempted.

## What this PR adds

1. **Pinned actual-source integration, not a hand-written B4 surrogate:** four real installed post/reversal function definitions were copied by SELECT-only catalog inspection to `scripts/sql-fixtures/gate58-b4-catalog-snapshot-20261118.sql`. The file is explicitly FOR DISPOSABLE TESTS ONLY, not a production migration; compare its fingerprints before treating the behavior as current.
2. **Separate PostgreSQL service/job:** `.github/workflows/onexa-manual-journal-real-b4.yml` uses a clean disposable database, synthetic tenant/account/legal entity/branch/role/fiscal-period parent schema, the captured REAL B4 functions and the actual Gate58 SQL. It does not load the fake B4 publisher.
3. **Behavioral acceptance:** `gate58-real-b4-post-reverse-smoke.sql` checks an open period and finance-approved source, GL source id/revision, period id, totals, ledger lines and project/cost-centre dimensions, registry non-duplication, retry idempotency, closed-period post denial without partial posting, open-period restart, closed-period reverse denial, successful linked reversal in a new open month and cross-tenant denial. All rows and synthetic period updates are rolled back.
4. **Fail-closed Gate58 B4 receipts:** After `onexa_post_journal`, Gate58 now verifies the returned GL header exists within the same tenant, same legal entity/currency/date, approved source id/type/revision, exact debit/credit and `posted` state before updating the manual journal. After `onexa_reverse_journal`, Gate58 verifies the matching posted reversal header, contra totals and original-header reversal link/state before changing the manual status. Incorrect B4 responses roll back atomically.
5. **Hostile adapter tests:** `gate58-b4-invalid-receipt-smoke.sql` intentionally spoofs wrong B4 response headers and orphan reversal UUIDs, proving Gate58 does not persist false posted/reversed statuses or orphan test ledger rows.
6. **Read-only operator audit:** `supabase/manual-packages/gate58_b4_live_contract_readonly.sql` inventories installed B4 functions, their fingerprints and period/idempotency behavior, without reading customer journal data or changing roles. A checksum-guarded **review-only** patch updates the hosted Gate58 post handler when independently approved. The existing lifecycle review-only package now contains the reversal receipt check.

## Known limitations and release criteria

- Parent GL tables, tenant claims, role authorization and periods in CI are intentionally synthetic. Captured B4 function bodies are real, but this **does not prove compatibility with independent Staging or all actual finance roles**.
- The core B4 tolerance, multi-currency precision, account freeze/policy and historical ledger differences require separate cross-module audit. Do not force a global shared-B4 change without evaluating legitimate rounding and historical entries.
- New post/reversal receipt guards are source-only; already-installed Gate58 functions still require separately reviewed, fingerprint-guarded updates. The new post patch and existing lifecycle/reversal patch must be staged in a verified release sequence; failing checksum is STOP.
- No independent ONEXA Staging project, restorable production-clone evidence, formal finance/security approval, live save/print UAT or authorization for customer posting has been demonstrated.
- No hosted SQL DDL/DML, production journal, tenant membership or environment flag was changed.

**Release decision: HOLD.** All findings and local green tests, even when achieved, do not mean the production ERP is activated.
