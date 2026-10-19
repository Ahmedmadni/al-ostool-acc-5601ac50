# Gates 104–110 — Finance denial and reversal regression

This group expands the disposable PostgreSQL smoke using real Gate42 project-cost posting and real Gate64 approval triggers with synthetic tenant data.

- **G104:** Assigned poster with no tenant context cannot post.
- **G105:** A UUID without membership / module posting grant cannot post, even if a tenant hint is set.
- **G106:** Invalid calendar month (2026-13) is denied, and rejected attempts leave no ledger or cost posting.
- **G107:** Retrying a project-cost post after its original journal was marked reversed must raise the explicit reversed-or-missing journal error, not create a new journal.
- **G108:** The historical posting/journal count remains one after the rejected reversed retry.
- **G109:** CI source contract verifies these guards remain in the real Gate42+Gate64 disposable smoke test.
- **G110:** This gate documents the **release boundary**: ephemeral fixtures are not hosted Staging; no validated real-account mappings, production schema or end-user identity integration. Separate staging and finance-approved mapping remain blockers.

All monetary values and identities in these tests are synthetic. This is not a production rollout or an IFRS attestation. Never run the temporary destructive tests against production.
