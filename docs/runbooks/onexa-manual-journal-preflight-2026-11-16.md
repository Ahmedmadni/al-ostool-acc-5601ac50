# ONEXA — Gate 58 journal editor hardening and remaining acceptance (2026-11-16)

## Scope of this source-only increment

The manual-journal editor was reviewed against the existing Gate 58 database RPC and the November 12 development report. In particular, the prior `Number(input) || 0` checks and `difference > 0.005` could misclassify invalid or non-finite values, and a failed second RPC could leave a successfully saved draft with no obvious resubmission path.

This change:
1. Evaluates draft totals in exact 1/10,000 units using `BigInt`, applies the ISO currency's permitted fraction digits, validates date/calendar, and requires available entity, branch and detail account selections. It refuses invalid/unsafe values before RPC.
2. Displays exact debit/credit/difference and first actionable validation error, preserves a local rather than UTC default date, and avoids duplicate React line keys on rapid additions.
3. Distinguishes draft-save success from submission confirmation, and exposes creator-only submission retry from the list. Identity/setup errors fail closed; database role enforcement is unchanged.
4. Rejects omitted debit/credit (and null line numbers) in the **versioned source** of the Gate 58 SQL function, adding a negative rollback-only smoke scenario.
5. Adds a runtime unit test for accepted SAR/KWD/JPY values, decimal balance, invalid dates, unauthorized dropdown selection, unsafe amounts, exponent/Infinity and precision errors, wired into the ordinary `npm run verify` suite.

## What this does NOT authorize or establish

- It does **not** apply `gate58_manual_journal_workflow.sql` to any hosted database or migrate existing tenant data.
- It does **not** enable `VITE_ENABLE_ONEXA_POSTING` or `VITE_ENABLE_ONEXA_MANUAL_JOURNALS`; both continue to be off by default.
- It does **not** prove the connected Lovable customer instance is up to date or that a separate Staging environment exists.
- It does **not** replace server-side permission checks, financial approval, fiscal-period validation, source-to-ledger reconciliation or tested backup restoration.
- The two separate create/submit RPCs still cannot promise atomic save-and-submit. Failure must be shown as an unconfirmed submission and the persisted draft must be reloaded; this avoids false success claims.

## Verification commands

```sh
npm run typecheck
npm run check:gate58-manual-journals
npm run test:manual-journal-validation
npm run verify
```

GitHub PR workflows are **Interface Readiness** (typecheck, build, verification) and **Native ONEXA SQL (Disposable PostgreSQL)**. Do not equate a green CI result with a hosted Gate 58 smoke test.

## Further work, in dependency order

- [ ] Finish a **dedicated isolated Staging environment** and prove that its Supabase ref and credentials differ from production. Use synthetic tenant and account data only.
- [ ] Confirm installed Gate 58 prerequisites (B4, tenant/RLS, legal entity/branch, finance permissions, fiscal periods and posting/reversal RPCs), version diffs, and the approved GL account roles.
- [ ] Run the Gate 58 rollback-only SQL smoke in Staging, including this missing-debit/credit rejection path, denied self-approval, tenant B access denial, posting retries, reversal and source-to-ledger reconciliation.
- [ ] Execute browser acceptance with distinct authorized creator, approver and poster accounts. Simulate a failed submit after successful create, refresh the page and prove the saved draft can be submitted exactly once.
- [ ] Review the non-atomic create/submit behavior for a future database-side atomic operation if business requirements demand it; never assume network failure means the RPC failed.
- [ ] Obtain financial sign-off, backup/restore evidence, change window and explicit production activation approval before enabling any accounting flags.

**Release decision: HOLD** until all hosted and financial acceptance conditions are met. 
