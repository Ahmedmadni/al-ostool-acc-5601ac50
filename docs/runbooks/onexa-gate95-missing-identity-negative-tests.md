# Gate 95 — Missing user / tenant identity denial

Adds two negative scenarios in disposable PostgreSQL for the native operations fixture. When an authenticated database role has a tenant hint but no `auth.uid()` identity, sites, work orders, and unpaid maintenance sources must return zero rows and the company/module access RPC must deny access. The opposite situation (valid user ID but no current tenant claim) must also return zero rows and deny module access. After the checks, synthetic identity context is restored for the remaining fixture steps.

This tests mocked claim helpers and real native Gate71–75 policies on temporary PostgreSQL, **not live Supabase authentication**. A hosted isolated Staging project with distinct users/tenants remains mandatory before any production rollout.
