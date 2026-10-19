# ONEXA Gates 96–100 — Synthetic finance posting integrity

**G96:** Check the real Gate42 journal and project-cost posting share tenant, legal entity, SAR currency, 125 SAR synthetic amount and balanced journal totals. This is a fixture-specific assertion, **not** a real company amount.

**G97:** A single Gate64 posted approval decision must refer to the exact journal UUID created by Gate42 and be attributed to the assigned poster, including after idempotent retry.

**G98:** Simulated original-journal reversal must not remove posted-approval audit or the linked and reviewed unpaid maintenance source; reconciliation must cease to report it as current reconciled cost.

**G99:** Source-contract checker fails if the above assertions (or previous separation/idempotency/reversal guard) disappear or stop running in the PostgreSQL workflow.

**G100 — Acceptance boundary:** This suite executes the **actual** Gate42 and Gate64 SQL packages against synthetic parent tables and helpers in ephemeral PostgreSQL 16. It does **not** prove correctness of production parents, complete journal lines, fiscal-period locks, actual Supabase auth, IFRS compliance, ZATCA settings, backup/restore or actual staging readiness. The 125 SAR fixture total is deliberately synthetic. The production engine remains blocked until independently authorized Staging and finance mappings, complete two-tenant acceptance tests, a restore rehearsal and signoff.

No production or hosted staging DDL/DML, ledger posts, role grants, or feature flags are changed.

**Gates 101–103:** The actual Gate42 posting RPC must reject a known document UUID from tenant B as `ONEXA_DOCUMENT_NOT_FOUND`, an invalid accounting period as `ONEXA_PROJECT_COST_PERIOD_REQUIRED`, and an absent user identity as `ONEXA_AUTHENTICATED_TENANT_REQUIRED`. Each denied attempt is tested before the authorized posting and must leave no project-cost posting or GL journal row. These cases run only against synthetic temporary PostgreSQL parent fixtures.
