# Gate 78 — Actual Gate 64 posting-approval guards in disposable PostgreSQL

**Status: automated isolated PostgreSQL integration only; NOT deployed to production.**

This Gate78 job compiles the **actual** `gate42_project_costs.sql`, then the **actual** `gate64_approval_posting_bridge.sql`, then the native Gate71–75 SQL in a fresh GitHub PostgreSQL 16 database.

The synthetic bootstrap mimics only the Gate63 **parent approval instance/step/decision tables and actor-selection contract**, plus six non-accounting posting-engine placeholders required by Gate64's seven-engine patch preflight. Gate64's definition-patching, before-update posting-authorization trigger, after-update completion trigger, decision record and accounting inbox are **real source SQL**, not approximations.

The negative test tries posting a synthetic project-cost document from a user who has `projects.post` but **is not assigned** to the active Gate64 post step. It requires the real Gate64 trigger to reject the attempt, atomically rolling back the Gate42 document status, G42 posting registry and B4 contract-double journal. It requires the approval instance to remain `awaiting_post`. A separately assigned poster must then succeed; the real Gate64 completion trigger must update the approval instance to `completed` and write the `posted` decision referencing the original GL journal.

The smoke also retains the two-tenant negative access checks, original project-cost idempotency test, Gate74 attribution, Gate75 evidence linkage, and reversal exclusion. No production data, credentials or customer tenant identifiers are loaded.

## Limits / production readiness

The real Gate63 approval configuration engine, full real B4 journal publisher, supplier/stock/payroll sources and real ONEXA tenant role schema are still outside this test. **Never treat stub Gate63 approval steps or the synthetic B4 publisher as proof that the actual financial approval/ledger sequence works on the connected customer schema.**

Before considering a migration: obtain an independently restorable staging clone of the actual tenant schema; verify G42 account mappings `project_wip_or_expense` and `cost_source_or_clearing`, G63/G64 workflows, every required posting RPC and current fiscal period, complete all tenant negative tests, and reconcile finance statements. Current customer production should be inspected **SELECT-only**. No DDL, seed tenants, status flips or postings to the live data plane without explicit approval and a backup.
