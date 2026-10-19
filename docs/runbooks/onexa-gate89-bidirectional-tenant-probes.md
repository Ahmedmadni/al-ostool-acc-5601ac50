# Gate 89 — Bidirectional tenant UUID isolation

Extends the disposable PostgreSQL test to check the reverse tenant boundary (tenant B cannot directly read tenant A site, asset, work order, or approved unpaid maintenance source by known UUID). Gate 88 already checks tenant A to B for native sites/assets/orders; Gate 89 tests B to A and an additional sensitive finance-related source. The fixture restores tenant A claim identity for subsequent existing assertions.

This is synthetic PostgreSQL under mocked authentication and tenant claim helpers; it does not prove Supabase hosted RLS or live multitenant authorization. No production or hosted Staging SQL is executed.
