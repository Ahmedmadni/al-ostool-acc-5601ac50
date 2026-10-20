# Gates 121–125 — Reconciliation continuity and cross-tenant access

The actual Gate42/G64 posting and Gate71–75 maintenance packages are exercised on synthetic parent schema in disposable PostgreSQL.

- Gate121 requires one linked evidence source with matching tenant/document after an independent finance review and successful posting.
- Gate122 tests direct lookup of tenant A source and source-reconciliation view under authenticated tenant B context, requiring zero rows.
- Gate123 checks historical source/document linkage remains after a simulated original journal reversal; the old cost must no longer be reported as currently reconciled.
- Gate124 prevents CI regression by guarding markers in the real G42/G64 smoke fixture, run in all three SQL jobs.
- Gate125 is a release boundary: these checks do not validate hosted Supabase, IFRS mappings, all GL lines, backup restores, real user roles or independent Staging. Production migrations and posting remain blocked without separate approval.

Do not execute the synthetic fixtures against customer production.
