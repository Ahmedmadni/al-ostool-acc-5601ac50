# ONEXA development acceptance

- [x] Resume November 12 development: revalidate approved HR fixes, test Gate 71 prerequisites, and document remaining rollout blockers.

- [x] Run latest HR migrations locally using synthetic tenants; test calculation, draft, refresh, denial and isolation.
- [x] Consolidate Gates 42/63/64/71–75 and B4 dependencies using catalog-only inspection.
- [x] Deliver test evidence, defects and approval boundaries.
- [x] Apply HR hardening (negative leave override, cross-tenant clearance) — applied November 12; final migration passed 32/32 synthetic tests and two persisted regression cases; production catalog guards and grants confirmed.
- [x] Validate Gate 71 in independent synthetic PostgreSQL — 25/25 behavioral checks; all eight postcheck objects ready and expected grant matrix verified.
- [ ] Apply Gate 71 tenant-company bridge — approved November 8; blocked by missing tested customer-clone/backup restore evidence and reviewed index-lock window; synthetic tests do not clear this requirement. Feature remains off; no mappings provisioned.
- [ ] Apply Gates 72→73→42→74→64→75→B4 — blocked: per-gate production approval or approved independent testing plan.
- [ ] Hosted save/readback/print acceptance — blocked: available injected session has no usable tenant claim; browser remained loading, with no save button. Production test settlements remain unauthorized.
