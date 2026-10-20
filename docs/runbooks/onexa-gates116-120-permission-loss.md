# Gates 116–120 — Permission loss and recovery regression

These checks use a **disposable PostgreSQL 16 test service only**, guarded by its `onexa_gate_test` database name. They deliberately revoke permissions to prove that the *existing* Gate90 privilege contract detects loss of access as well as unwanted escalation.

- **116:** Revoke authenticated SELECT on a native asset table; require the exact missing-read failure.
- **117:** Revoke authenticated EXECUTE on the controlled asset-creation RPC; require the exact missing-RPC failure.
- **118:** Restore both grants via a shell EXIT trap and rerun the entire Gate90 contract successfully.
- **119:** Execute these controls in all three independent PostgreSQL jobs after installing Gates 71–75.
- **120:** Release safety boundary: these are role/privilege checks with mocked identities, not proof of real Supabase JWT/RLS, GL completeness, actual hosted Staging, or approved account mappings. Production migration and posting are still blocked.

Never execute this shell script on production or on a remotely hosted Staging environment.
