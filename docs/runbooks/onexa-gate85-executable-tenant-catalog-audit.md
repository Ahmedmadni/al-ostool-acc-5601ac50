# Gate 85 — Execute the real Gate 84 tenant catalog queries in disposable PostgreSQL

This phase closes a verification gap: Gate 84 originally checked the catalog report's **source text**, but did not execute its SQL. Gate 85 executes the unchanged `gate84_tenant_boundary_catalog_readonly.sql` in **each of the three temporary PostgreSQL 16 GitHub Actions jobs**, after fixture schema creation and Gates 71–75 installation and before each job's behavioral smoke script.

The existing `psql -X -v ON_ERROR_STOP=1` causes any syntax, missing-catalog-column or SQL execution failure to fail the PR. This cannot certify the *contents* of production catalog results or prove tenant RLS, as fixture parent tables are synthetic. The separate two-tenant negative tests continue to test isolation in those fixtures.

No hosted Supabase project, user data, secrets or accounting entries are accessed. No new migration is created. Production remains deployment-blocked pending a separately approved, isolated Staging environment and finance mapping sign-off.
