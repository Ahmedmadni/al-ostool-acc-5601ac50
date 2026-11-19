# ONEXA — Phase 9: Exact B4 and Gate 58 reversal replay integrity

Date: November 19, 2026

## Verified installed reversal issue

Read-only catalog inspection confirmed the production definitions:

- `onexa_private.reverse_journal(uuid,date,text,text)`: `f51a890027057a0e838c13cbfd6ddb61`
- `public.onexa_reverse_manual_journal(uuid,date,text,text)`: `0b72dab37dd9057dde187102cfe2dce7`

Both historically return an existing reversal journal UUID whenever the original is already reversed, **before comparing the new accounting date, period or explanation to the original instruction**. Therefore a retried request with a different accounting treatment can receive a false successful response. The installed original B4 code is preserved in `scripts/sql-fixtures/gate58-b4-catalog-snapshot-20261118.sql` for reproducible negative testing.

## Source-only corrections

### B4 shared reversal

`supabase/manual-packages/gate58_b4_reversal_idempotency_REVIEW_ONLY.sql` proposes a checksum-guarded replacement of **only** the installed private B4 reversal function. When an original journal is already reversed, it checks the linked reversal journal before returning the old UUID:

- Same tenant and legal entity; authentic original `reversal_journal_id` and reverse `reversal_of_id` link.
- `journal_reversal` source type, source reference and revision; `posted` reversal state.
- Exact date, selected fiscal period code and period date interval, regardless of whether the historical period has since closed. **No new posting is allowed to bypass the existing B4 open-period rule.**
- Exact original currency, inverse debit/credit totals, stored source snapshot containing the recorded reason, and reversal memo.
- Every reversing GL line compared against the ordered originals: account, debit/credit swap, reason-bearing description, dimensions/project/cost centre, and tenant.

Any mismatch raises `ONEXA_B4_REVERSAL_PAYLOAD_CONFLICT` instead of returning a misleading successful UUID. A newly created reversal also checks its posting receipt (including amount/source/date/period) before marking the original reversed. This avoids accepting an unexpected upstream posting registry response.

The built-in rule forbidding reversal-of-reversal is now checked **before** an already-reversed early return.

### Gate 58

The authoritative `gate58_manual_journal_workflow.sql` and its corresponding `gate58_lifecycle_authorization_patch_REVIEW_ONLY.sql` now independently verify the original and contra GL receipts for repeated reversal calls. A mismatch raises `ONEXA_MANUAL_JOURNAL_REVERSAL_REPLAY_CONFLICT`. Gate 58 normalizes leading/trailing reason whitespace with `btrim`, and keeps the original period-code/date syntax validation. An identical historical retry does not create a new event.

To ensure its **separate** disposable fake publisher continues to support realistic Gate58 tests, the synthetic adapter was extended with fiscal periods, source snapshots, GL lines, and matching reversal descriptions and links. This does not replace real B4 integration: the actual B4 SQL runs separately.

## Automated evidence

The `B4 Shared GL Foundation Integrity` GitHub Actions job now:

1. Reproduces the deployed legacy B4 flaw on synthetic tenant and finance data, by reversing a sales journal and then submitting changed dates/reasons/period codes. It confirms the original code misleadingly returns the prior reversal ID; all data is rolled back.
2. Installs the checksum-reviewable candidate B4 reversal definition in a disposable PostgreSQL database. Static tests require the tested function body and proposed review-only SQL to match exactly.
3. Exercises identical reverse retries after the original period is **closed**, invalid reasons/dates/periods, corrupt reversal snapshot/memo/lines, broken links, altered contra totals, no duplicate registry or audit events, and cross-tenant denial.
4. Executes the actual authoritative Gate58 SQL and source-specific replay checks, including normalized reason text and invalid accounting dates, with one immutable contra ledger.
5. Runs **two separate database sessions** reversing the same synthetic original with different dates and reasons while the first transaction holds the original row lock. Exactly one reversal, one registry posting and one reversal audit event are permitted; the second request must fail with the specific payload-conflict exception.
6. Preserves existing source/idempotency and accounting-period tests from phases 6–8.

The read-only `gate58_b4_live_contract_readonly.sql` reports separately whether the B4 and Gate58 reversal replay guards are installed, without reading customer financial documents.

## Release blockers — HOLD

All modifications in this phase are to GitHub source, review-only SQL and disposable CI **only**. No DDL, postings, role change or reversal was executed against hosted company data.

Before activation: independently restored Staging; signed source snapshots and live function MD5 preflight; complete role/tenant verification; audit of legitimate finance-module reversal reasons/retry requirements; accounting manager and security approval; backup/restore and lock-window rehearsals; tested rollback plan. The previously discovered production GL type allowlist omission for `manual_journal`, 0.005 balance tolerance, and missing hosted Gate58 amendment remain blockers.

**Extra precision:** A passing test of captured real B4 code with synthetic parents does not prove a fully cloned production environment or production activation. The existing `review-only` packages remain deployable proposals, not executed migrations.
