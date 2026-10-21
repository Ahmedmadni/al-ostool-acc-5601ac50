# Gates 151–155 — Strict staging evidence shape

Gate151 rejects unknown top-level, production, staging, and validation fields, as well as malformed nested records. Gate152 adds negative cases for unreviewed fields and array-shaped records. Gate153 runs this test in three isolated SQL CI jobs. Gate154 preserves the earlier evidence checks for different project URLs, synthetic-only staging data, declared RLS checks and disabled writes. Gate155 keeps production and hosted Staging untouched; the manifest is a self-reported offline document, not proof of a deployed isolated Supabase project.

The check cannot authorize deployment, verify actual network connections, or replace real integration and restore testing.
