# Gate 88 — Cross-tenant direct UUID probes

The disposable PostgreSQL native two-tenant smoke now attempts direct row lookups of tenant B's known site, asset, and work-order UUIDs while operating under tenant A's authenticated claim. Each lookup must return no rows, otherwise the transaction aborts and CI fails.

This extends the pre-existing count-based RLS and forbidden RPC tests. The synthetic fixture runs in a separate GitHub Actions PostgreSQL service only. It is not a live staging or production tenant security certification, and does not test every table or all privilege permutations.

No Supabase production changes, customer records or new financial journal posts occur.
