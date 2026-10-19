# Gate 87 — RLS negative-control validation

The existing Gate 86 SQL verifies structural RLS metadata in disposable PostgreSQL. Gate 87 proves that guard actually fails when a known tenant table has RLS disabled, rather than only passing the expected healthy configuration.

The shell runner first verifies `current_database() = onexa_gate_test`, then temporarily disables RLS on `onexa_operations_work_orders` in the **disposable CI database only**, invokes the real Gate 86 SQL expecting the exact error `GATE86_RLS_DISABLED: onexa_operations_work_orders`, restores RLS via an exit trap, and checks the healthy schema passes again. It will fail CI if a false-positive success or a different error occurs.

This is a destructive *synthetic negative control*, **never run it on hosted Staging or production**. It does not test complete RLS predicates, live Supabase roles, or financial correctness.
