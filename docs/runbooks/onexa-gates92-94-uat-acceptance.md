# Gates 92–94 — Posting invariants and independent staging acceptance

## Gate 92 — Denied creator self-post

The **actual** Gate42 cost-posting RPC is invoked by the document creator under the **actual** Gate64 posting triggers in a disposable PostgreSQL fixture. The request must fail (unassigned poster, creator-poster separation, or explicit segregation) and leave **zero** project-cost postings and journal headers; the approval instance must remain awaiting-post.

## Gate 93 — Idempotent approval-post audit

After a separately assigned actor successfully posts the approved project-cost document, retry the same posting RPC. One and only one `posted` approval-decision record and one completed approval instance must remain. The existing smoke checks already require one journal and one project-cost posting, plus a correct reconciliation and reversal.

## Gate 94 — Staging/UAT release-blocker matrix

| Control | Evidence needed before approval | Current status |
| --- | --- | --- |
| Separate hosted Supabase Staging | Distinct project ref/URL, owner and region, accepted pricing | BLOCKED |
| No customer data or keys in Staging | Synthetic auth identities, two fictional tenants and service-key segregation | BLOCKED |
| Dependency baseline | Gate79 + Gate82 + Gate84 read-only catalog results | SOURCE READY, HOSTED NOT RUN |
| Install order | Verified B4, G35–43 engines, Gate42, Gate63, Gate64, then native Gates71–75 in approved order | BLOCKED |
| Finance mappings | Signed codes for `project_wip_or_expense` and `cost_source_or_clearing` | BLOCKED |
| Finance approvals | Real workflow assignment, separation, no unassigned post, no orphan journal | CI SYNTHETIC ONLY |
| Cost lifecycle | Source evidence, approval, one journal, attribution, reversal and reconciliation | CI SYNTHETIC ONLY |
| Security | Two separate auth users, two tenant scopes, direct UUID access denied both directions | CI SYNTHETIC ONLY |
| Effective privileges | anon denial, authenticated direct-write denial, RPC access and RLS under actual Supabase roles | CI SYNTHETIC ONLY |
| Recovery | Restorable database backup verified against Staging, migration rollback rehearsal | BLOCKED |
| Browser UAT | Real Lovable preview login/logout, blocked storage, multi-tab, role-specific buttons | BLOCKED |
| Go-live authorization | Written finance/security approvals and feature flags staged then authorized | BLOCKED |

**Non-negotiable:** CI success is NOT production release authorization. Never run legacy Gates 13–15 or Gate66 in the multi-tenant production schema. Gate64 is not standalone and production DDL/DML, posting and flags remain prohibited without approval.
