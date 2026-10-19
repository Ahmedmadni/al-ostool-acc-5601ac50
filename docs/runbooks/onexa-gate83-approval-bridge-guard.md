# Gate 83 — Approval-posting contract guard

This is a **source-only regression check** for the actual Gate 64 SQL. It fails when the source loses any of the seven finance posting prerequisites, missing-Gate63/engine aborts, patch ambiguity protection, assigned post-step check, required approval instance, separation of duties, trigger state transition guard, security-invoker accounting inbox or explicit RPC grants. It also confirms the real Gate 42 RPC and disposable PostgreSQL Gate 64 smoke fixture remain connected.

Run: `node scripts/check-gate83-approval-bridge-contract.mjs`.

Limits: text assertions do not substitute for parser analysis, permissions audit, realistic RLS testing or installed production/staging verification. Gate 78's ephemeral fixture still simulates the real B4 and Gate63 dynamic engine. No live data, credentials, production migration or feature-flag modification is involved.

Next production prerequisite remains a distinct user-approved Staging project, verified schema dependency sequence, finance-approved account-role mappings and end-to-end synthetic tenant tests. Gate 64 must never be installed alone.
