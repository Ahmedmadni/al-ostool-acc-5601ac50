# Gates 146–150 — Offline Staging readiness evidence

This checks an explicitly supplied non-secret JSON document. It does not query Supabase, create projects, verify claims, approve a release, or alter a database.

- Gate146: Production and Staging Supabase HTTPS URLs and 20-character project refs must match internally and differ from one another.
- Gate147: Staging data must be declared synthetic only. Credential fields are rejected.
- Gate148: Require explicit separate-auth-user, tenant-RLS, restore-rehearsal and finance-mapping evidence flags. A true flag is a declaration, not proof.
- Gate149: Release authorization and both database-write approvals must remain false. A ready result means a manifest passes structural checks only, not permission to deploy.
- Gate150: Run positive and negative test cases in pull-request CI.

Run: node scripts/audit-staging-evidence.mjs path/to/private-evidence.json

Example manifest with fake project IDs (NOT actual approval evidence):

    {
      "production":{"project_ref":"aaaaaaaaaaaaaaaaaaaa","supabase_url":"https://aaaaaaaaaaaaaaaaaaaa.supabase.co/","database_write_approval":false},
      "staging":{"project_ref":"bbbbbbbbbbbbbbbbbbbb","supabase_url":"https://bbbbbbbbbbbbbbbbbbbb.supabase.co/","data_classification":"synthetic_only","database_write_approval":false},
      "validation":{"separate_auth_users_confirmed":true,"tenant_rls_test_passed":true,"staging_restore_test_passed":true,"finance_mapping_approved":true,"release_authorized":false}
    }

Never put actual secrets in manifests. Never run synthetic fixtures on production. Independent hosted Staging is still not established.
