# ONEXA — Phase 2: hosted Gate 58 parity and disposable SQL exercise (2026-11-16)

## Current finding (read-only Lovable customer catalog)

The project has a Supabase-backed database. Inspection was restricted to `pg_catalog` / function metadata; no customer journal, employee or accounting rows were selected or mutated.

| Check | Observed |
| --- | --- |
| Gate 58 create/transition/post/reverse routines | Present |
| Gate 58 journals, lines, events | Present |
| Gate 58 reconciliation view | Present |
| Gate 58 table RLS | Enabled on 3 of 3 inspected tables |
| Anonymous EXECUTE on four Gate 58 routines | 0 |
| B4 reversal routine | Present |
| Live create RPC explicit null debit/credit check | **Absent** |
| Live create RPC date-versus-period equality check | **Absent** |
| Gate 71 company-scope table / Gate 72+ native operations tables | Absent in sampled catalog |
| Project-cost centers/posting tables | Absent in sampled catalog |

Observed live `onexa_create_manual_journal` definition MD5 on PostgreSQL 17.6: `0a8e73d608b3642837209b5334c7477a`. This is an **observational checksum**, not an access credential, certification or deploy authorization.

**Material problem:** PR #99 corrected the source Gate 58 SQL, but did not update the already-installed customer RPC. A browser-side input guard is not an accounting control. Database validation must be fixed and independently tested before Gate 58 can be activated.

## Phase 2 delivered in source control

1. Strengthened the authoritative Gate 58 create-RPC source to reject mismatched date and `YYYY-MM` fiscal period.
2. Prepared a standalone, review-only patch for the already-installed create RPC. It requires **exact** known live function-definition MD5 before replacing the body, and leaves all existing data, grants, workflow status and flags untouched. Any drift fails closed. **Do not execute without approvals.**
3. Added `gate58_live_compatibility_readonly.sql` for future catalog-only reinspection (RLS, grants, routine presence, null and period guards).
4. Added a fourth isolated disposable PostgreSQL CI job. It compiles the **real** Gate 58 SQL and executes real creation, maker/checker denial, posted-journal source linkage, retry idempotency, reversal and negative cross-tenant probes against exclusively synthetic fixture data.
5. The disposable job uses a deliberately **mock B4** journal publisher, not the real B4 publisher. It demonstrates Gate 58's integration contract and SQL execution, **not** production ledger acceptance, account-code authorization or a tested hosted restore.

## Next approvals and acceptance gates

1. **Dedicated hosted ONEXA Staging:** establish ownership, cost/region, project identity and isolation. Never restore or reuse unrelated inactive projects without approval.
2. **Restore and migration evidence:** rehearse a restore and approved migration ordering against isolated data; compare live schema and function signatures with the staging baseline.
3. **Accounting acceptance:** confirm real B4 journal publisher, posting/reversal, fiscal-period lock, chart of accounts, finance roles, maker/approver/poster separation, source-to-ledger and balance-sheet reconciliation. A synthetic 125.25 test is not a booking authorization.
4. **Hosted browser test:** use distinct authorized test identities; create, refresh, re-submit after partial network failure, approve, post, reverse, print and verify persistence, under the proper tenant. Check unauthorized-role and cross-tenant negative cases.
5. **Operational gates 71–75, 42, 64:** follow dependency and mapping runbooks; the GitHub files cannot be considered deployed to the customer database.
6. Only then consider an **explicitly approved** production change window, backup verification, privilege review and flip of `VITE_ENABLE_ONEXA_POSTING` / `VITE_ENABLE_ONEXA_MANUAL_JOURNALS`.

## Current release decision

**HOLD.** SQL source patches and green CI never authorize mutations of customer production. No Staging was created, no customer function replaced, no accounting transaction inserted, and no production flags enabled during this phase.
