# Gates 161–165 — Staging-only health preflight

This optional CLI supplies a **read-only Staging HTTPS health request** after the existing manifest declares separate Supabase project identifiers and all readiness checks.

- Gate161: refuse any manifest rejected by the offline audit (including incomplete finance/RLS/recovery declarations).
- Gate162: refuse matching production/Staging origins. Target URL is derived only from the reviewed Staging Supabase domain.
- Gate163: permit only `GET /auth/v1/health`, without API keys, cookies, Authorization, redirects, DB queries, migrations, or mutation.
- Gate164: use mocked fetch tests in CI; CI never contacts hosted Supabase.
- Gate165: require an explicit CLI `--staging-health-only` flag; responses report only status, and reaching the health endpoint does not establish real tenant isolation, DB privilege safety, or UAT acceptance.

Usage (only after an **independently provisioned and reviewed** Staging exists):

`node scripts/probe-staging-health.mjs private-evidence.json --staging-health-only`

Never enter secrets or production credentials in the manifest. This utility **does not create Staging** or approve a release. Real hosted staging is still unverified until reviewed separately.
