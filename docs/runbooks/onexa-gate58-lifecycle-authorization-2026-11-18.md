# ONEXA — Phase 4: manual-journal lifecycle authorization and constraint safety (2026-11-18)

## Verified catalog baseline (read-only, connected Lovable project)

- The installed `public.onexa_transition_manual_journal(uuid,text,text)` has definition MD5 `6be0100c16f4594132af3ac119afdc3a`.
- The installed `public.onexa_reverse_manual_journal(uuid,date,text,text)` has definition MD5 `0b72dab37dd9057dde187102cfe2dce7`.
- The installed table constraint `onexa_manual_journals_balanced` is `CHECK (abs(total_debit - total_credit) <= 0.005)`.
- These are **catalog observations**, not evidence that a hosted Staging project or a restorable backup exists.

## Critical defects addressed in repository code

1. **Rejection was incorrectly authorized by `finance.create`, not `finance.approve`**. A creator who had only entry permission could reject someone else's submitted journal, and the original creator could reject their own. Rejection now requires the reviewer entitlement and refuses creator self-rejection, while preserving rejection reasons and audit events.
2. **Cancellation used `finance.create` without requiring the original creator.** A separate finance creator could cancel a colleague's draft or submitted journal. Cancellation is now creator-only, and cancelling a submitted journal requires a documented reason.
3. **Reversal accepted mismatched or absent date/period arguments before invoking B4.** Gate 58 now rejects these early. Actual B4 must separately enforce **closed fiscal periods and finance locks**; this change is not a substitute.
4. **Fresh Gate 58 installs used a permissive table-level balance constraint.** The source schema now requires exact equality of header debit and credit independent of the function. An existing installed constraint is **not** updated by merely merging the repo or replaying `CREATE TABLE IF NOT EXISTS`.

## Verification and safe migration artefacts

- Run the actual Gate 58 SQL on a disposable PostgreSQL fixture: unauthorized rejection, self-rejection, cancellation by another creator, no-reason cancellation, authorized review with an audit reason, creator reopening, valid owner cancellation, null/mismatched reversal period, and sub-cent unbalanced header attempted with privileged SQL. Every rejected operation runs in an exception subtransaction and the overall synthetic workflow is rolled back.
- `gate58_lifecycle_authorization_patch_REVIEW_ONLY.sql` replaces only the two live RPC definitions after exact observed MD5 preflight. It must not be executed automatically.
- `gate58_exact_balance_constraint_patch_REVIEW_ONLY.sql` checks that the installed constraint is exactly the expected legacy definition and that **no historical unbalanced headers** exist; otherwise it aborts. Altering table constraints needs a planned lock/maintenance window and a tested independent restore.
- Source contract tests ensure guarded patches exactly mirror the versioned functions and require the new negative cases.

## Unfinished blockers

- Separate, identified ONEXA Staging with isolated credentials, synthetic tenants, finance roles and provable restore.
- Historical journal analysis with finance approval and a plan for any legitimate differences; never auto-balance, delete, rewrite or repost historical financial data.
- B4 posting/reversal acceptance, real currency precision and **closed-period** enforcement; approval/denial UI and role mapping; browser refresh/save/readback/print.
- **Rejected-to-draft is not an editing workflow:** the current panel cannot revise journal lines. Either build a governed revision/edit RPC with audit history or require a new journal. Do not claim that rejected journal corrections are supported yet.
- Production change authorization, security sign-off, permission review, explicit opt-in feature flags and a backout procedure.

**Release decision: HOLD.** No connected hosted SQL, customer journal, production flag or role mapping was modified in this phase. `main` only receives source/CI changes after tests pass.
