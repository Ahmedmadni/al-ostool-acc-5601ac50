# Gate 90 — Anonymous and direct-write permission matrix

Runs PostgreSQL privilege assertions on eight native tenant-bearing tables and seven controlled RPC signatures in all three disposable CI jobs. Anon must have no direct table access nor execute any listed RPC. Authenticated users must have SELECT but **not** direct INSERT/UPDATE/DELETE/TRUNCATE on these tables; controlled RPC execute remains available to authenticated sessions.

This is catalog privilege inspection in synthetic PostgreSQL, not proof of Supabase effective roles, RLS predicate correctness, or production access. Requires separate Staging behavioral tests. Never run destructive fixtures on production. No production changes.
