# Gate 84 — Tenant boundary read-only audit

Adds a **catalog-only diagnostic**, `supabase/manual-packages/gate84_tenant_boundary_catalog_readonly.sql`, with three SELECTs: presence/RLS flags and policy counts for 14 relevant tenant-bearing tables, FK/unique/primary key metadata on ONEXA tables, and policy definitions for five high-risk areas. Output is database metadata; do not append data samples or real customer identifiers.

**Interpretation:** Missing tables and disabled RLS are hard blockers; having policies or a tenant_id column in an FK is not proof of correct tenant isolation. Review referenced columns, effective roles, SECURITY DEFINER behavior, grants and actual tests with two *synthetic* users and tenants in a separate Staging database. A single-column FK might be acceptable for a globally unique PK, so the `REVIEW_CROSS_TENANT_FK` marker is a prompt for inspection, not proof of vulnerability.

This phase only records metadata and protects the SQL with `scripts/check-gate84-tenant-boundary-readonly.mjs` in isolated GitHub CI. No Supabase project was created or production database queried/mutated. **No approval for Gates 42, 64, 71–75 deployment.**
