# ONEXA development acceptance

- [x] Run latest HR migrations locally using synthetic tenants; test calculation, draft, refresh, denial and isolation.
- [x] Consolidate Gates 42/63/64/71–75 and B4 dependencies using catalog-only inspection.
- [x] Deliver test evidence, defects and approval boundaries.
- [ ] Apply HR hardening (negative leave override, cross-tenant clearance) — blocked: explicit production approval.
- [ ] Apply Gates 71→72→73→42→74→64→75→B4 — blocked: per-gate production approval or a Staging project.
- [ ] Hosted save/readback/print acceptance — blocked: user session carrying tenant claim.
