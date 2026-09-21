import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const files = {
  b2: "supabase/manual-packages/b2_onexa_legacy_tenant_boundary.sql",
  b2check: "supabase/manual-packages/b2_onexa_legacy_tenant_boundary_postcheck.sql",
  b3: "supabase/manual-packages/b3_onexa_role_and_posting_authorization.sql",
  b3check: "supabase/manual-packages/b3_onexa_role_and_posting_authorization_postcheck.sql",
  gate35: "supabase/manual-packages/gate35_sales_inventory_posting.sql",
};

for (const path of Object.values(files)) assert.ok(existsSync(path), `missing ${path}`);
const b2 = readFileSync(files.b2, "utf8");
const b2check = readFileSync(files.b2check, "utf8");
const b3 = readFileSync(files.b3, "utf8");
const b3check = readFileSync(files.b3check, "utf8");
const gate35 = readFileSync(files.gate35, "utf8");

for (const marker of [
  "expected 98 legacy tables",
  "'request.jwt.claims'",
  "ONEXA_B2_MIGRATION_TENANT_CONTEXT_FAILED",
  "_target.table_name <> 'audit_logs'",
  "update public.audit_logs",
  "add column if not exists tenant_id text",
  "as restrictive for all to authenticated",
  "onexa_private.is_active_member(auth.uid())",
  "references public.onexa_workspace(tenant_id)",
  "revoke all on table public.%I from public, anon",
]) assert.ok(b2.includes(marker), `B2 invariant missing: ${marker}`);

assert.match(
  b2,
  /set_config\([\s\S]*?'request\.jwt\.claims'[\s\S]*?true\s*\)/,
  "B2 migration tenant claim must be transaction-local",
);

assert.ok(b2check.includes("count(*) = 98") && b2check.includes("bool_and(status = 'ready')"), "B2 postcheck summary is incomplete");

for (const marker of [
  "onexa_private.has_module_action",
  "membership.role_key = 'workspace_owner'",
  "'hr_manager', 'auditor_readonly'",
  "ONEXA_JOURNAL_POST_NOT_AUTHORIZED",
  "ONEXA_JOURNAL_REVERSE_NOT_AUTHORIZED",
  "ONEXA_DOCUMENT_CREATE_NOT_AUTHORIZED",
  "ONEXA_DOCUMENT_TRANSITION_NOT_AUTHORIZED",
  "onexa_create_business_document_unchecked",
  "onexa_transition_business_document_unchecked",
  "onexa_post_journal_unchecked",
  "onexa_reverse_journal_unchecked",
]) assert.ok(b3.includes(marker), `B3 invariant missing: ${marker}`);

for (const signature of [
  "public.is_admin(uuid)",
  "public.has_role(uuid, public.app_role)",
  "public.user_has_any_role(uuid, text[])",
  "public.has_permission(uuid, text, text)",
]) assert.ok(b3.includes(`revoke all on function ${signature} from public, anon`), `legacy function is not closed to anon: ${signature}`);

assert.ok(b3check.includes("anon_execute_exposed") && b3check.includes("authenticated_execute_mismatch"), "B3 postcheck does not verify function ACLs");
assert.ok(gate35.includes("ONEXA_B3_MODULE_AUTHORIZATION_REQUIRED"), "Gate 35 does not require B3");
assert.ok(gate35.includes("ONEXA_SALES_POST_NOT_AUTHORIZED"), "Gate 35 does not enforce sales posting authorization");
assert.ok(gate35.includes("public.onexa_account_role_mappings"), "Gate 35 does not reuse the installed account mappings");
assert.ok(!gate35.includes("public.onexa_posting_account_roles"), "Gate 35 still contains the duplicate mapping table");

console.log("B2/B3 ONEXA production authorization checks passed ✓");
