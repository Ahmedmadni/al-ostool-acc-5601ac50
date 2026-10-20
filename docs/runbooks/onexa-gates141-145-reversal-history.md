# Gates 141–145 — Original journal continuity after reversal

- 141: The historical project-cost posting still links to the reversed original journal.
- 142: The business document's posted journal ID still equals the original project-cost posting's journal ID.
- 143: The reversed historical journal remains uniquely present and balanced for the synthetic 125 SAR fixture.
- 144: GitHub CI regression guard ensures the new checks and real Gate42/Gate64 fixture remain wired.
- 145: Safety boundary — PostgreSQL temporary test fixtures only; the test simulates reversal by changing journal state, **not** exercising a production-grade reversal RPC or verifying replacement journal lines. It does not certify actual hosted Supabase roles, real fiscal closure, Staging, or go-live readiness.

No production or hosted Staging database modification; actual account mappings and full finance acceptance remain blocked.
