# Gate 86 — Database-executed native tenant RLS assertions

This adds a **throwaway PostgreSQL-only** catalog assertion executed in all three CI jobs after real Gates 71–75 have been applied. For eight tenant-bearing tables it requires: table existence, enabled RLS, a `tenant_id` column and at least one SELECT/ALL policy. The test explicitly refuses execution unless `current_database()='onexa_gate_test'`.

This is a minimum structural safeguard, **not** proof that RLS predicates block cross-tenant access or that production migrations are safe. The existing two-tenant negative tests continue to cover simulated behavior. Neither this SQL fixture nor any migration is applied to Supabase or company production.

Approval to create separate hosted Staging, finance account-role mapping and functional UAT remains outstanding.
