# Gates 131–135 — Approval transitions and rejection atomicity

- 131: Denied finance posting attempts leave the actual Gate64 approval instance in awaiting-post state.
- 132: Denied attempts leave the original approved document and null posted journal identifier unchanged.
- 133: A simulated original journal reversal retains exactly one completed approval instance and completion timestamp.
- 134: CI source regression checker confirms these checks and the real Gate42/Gate64 SQL smoke remain wired in disposable PostgreSQL.
- 135: Release boundary—this is a synthetic PostgreSQL security/finance smoke using mocked parents and identities, not hosted Supabase Staging or approval for production. No production modifications are allowed.
