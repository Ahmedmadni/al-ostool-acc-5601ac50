# Gates 111–115 — Negative grants and release safety

These gates run against disposable PostgreSQL 16 in GitHub Actions; no Supabase server is contacted.

- **G111:** Temporarily grant `anon` EXECUTE on native site-creation RPC. Require Gate90 to reject with its exact anonymous RPC error.
- **G112:** Temporarily grant `authenticated` UPDATE on the work-order table. Require Gate90 to reject with its exact unauthorized direct-write error.
- **G113:** Revoke both artificial privileges in an exit trap, then rerun Gate90 successfully. Failed assertions exit nonzero.
- **G114:** CI enforces the negative-control script after the real Gates71–75 have been installed in disposable PostgreSQL.
- **G115:** Tests prove that the privilege contract catches these isolated regressions in a synthetic database, **not** effective Supabase production permissions. Hosted Staging, approved finance mappings, actual identity/RLS UAT, and backup/recovery testing remain required.

**Forbidden:** running this script on production, hosted Staging, or a database other than `onexa_gate_test`.
