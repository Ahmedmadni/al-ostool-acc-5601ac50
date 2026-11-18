# ONEXA — Phase 5: governed correction and resubmission of rejected journal entries (2026-11-18)

## Source and hosted reality

- Previous Gate 58 workflow could move a **rejected** document to `draft` without correcting any line, and the UI offered no amendment form.
- Existing journal header `revision` and event `event_data jsonb` support an atomic, audited revision without adding new tables.
- A read-only 2026-11-18 catalog query of the connected Lovable project confirmed `public.onexa_amend_manual_journal(uuid,integer,text,text,jsonb)` was **not installed**. The production RPCs and balance constraint remained legacy in the previous phase; GitHub merge cannot update hosted SQL.
- Dedicated, verified Staging and approved restore evidence are **still absent**. No hosted journal rows were queried.

## Changes in versioned source

1. **New server-authoritative RPC** `onexa_amend_manual_journal`:
   - Only original creator with `finance.create`, valid tenant claim and an authenticated identity can edit a `draft` or `rejected` entry.
   - Requires the exact expected revision, locks the header row `FOR UPDATE`, and refuses stale concurrent edits.
   - Immutable: journal ID/number, legal entity, branch, posting date, fiscal period and currency. Edits are only memo, external reference and line amounts/accounts/descriptions/dimensions.
   - Repeats real database checks: active legal entity/branch/account, two or more distinct numbered lines, one nonzero side per line, non-null explicit amounts, exact debit/credit balance, at most four decimal places (two for SAR).
   - In **one transaction**, copies original lines into an `amended` event snapshot; replaces lines; increments revision; resets submission/rejection approval metadata; sets status `draft`; captures full before/after snapshot including dimensions, totals, memo and reference.
   - Rejects edits after submission, approval, posting, cancellation or reversal. No update to GL headers or any already-posted transaction.
2. **Block audit bypass**: `onexa_transition_manual_journal('rejected' -> 'draft')` is no longer valid. A rejected journal must be amended through the new RPC, which increments revision and writes the audit event.
3. **Frontend**: Add edit buttons for creator-owned draft and rejected rows. Fetch the current header, line details and latest rejection reason using RLS, prefill the panel, lock immutable entity/branch/date and preserve the original cost-centre/project dimensions. Save a revision then submit it separately; an uncertain submission leaves an identifiable retryable draft. Stale edit errors fail closed.
4. **Read-only catalog checks and operator instructions** include the new RPC, the new static source contract test, and precise hosted-release limits.
5. **Real disposable PostgreSQL smoke test**: exercise both draft and rejected revisions, exact stored totals, prior/final line audit snapshots (including dimension values), owner checks, cross-tenant isolation, stale revision denial, incomplete and imbalanced inputs, SAR precision, refusal after submit/post, preserved rejection reason event, resubmission, approved version number reaching a fake B4 ledger header. The entire smoke rolls back; the B4 publisher is a **mock** and is not financial acceptance.

## Review-only hosted installation plan — not permission to deploy

- `gate58_amendment_REVIEW_ONLY.sql` adds the amendment RPC only if absent and only after the hardened creation/transition rules and exact balance table constraint are present. It refuses installation on the previous uncorrected foundation and never modifies rows.
- The existing separately guarded `gate58_lifecycle_authorization_patch_REVIEW_ONLY.sql` is synchronized with the new no-reopen rule. **The two patches form one coordinated release:** installing only the lifecycle patch could temporarily disable rejected resubmission until the amendment RPC is available. Both must be deployed and validated under an approved maintenance plan with feature flags off, proven independent restore, and rollback options.
- Check all grants (`anon` denied, `authenticated` permitted and server-side finance permissions enforced), RLS, revision conflicts, and historical snapshots before allowing real finance roles.
- Verify actual B4 closed fiscal-period rules and posting-idempotency semantics separately; the disposable adapter is intentionally not a B4 validation.
- Hosted browser save, refresh, reject, edit, submit, approve, post, reverse, print and export have not been accepted yet.

**Release status: HOLD.** Never run these packages against customer production, enable flags, import tenant data or execute financial test journals without explicit finance/security authorization.
