import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`,import.meta.url),"utf8");
const sql = read("supabase/manual-packages/gate79_onexa_staging_compatibility_readonly.sql");
const docs = read("docs/runbooks/onexa-gate79-staging-compatibility-readiness.md");
const pkg = JSON.parse(read("package.json"));
const checker = read("scripts/check-query-columns.mjs");
const inbox = read("src/lib/documents/business-document-service.ts");
const flags = read("src/lib/runtime-flags.ts");
const env = read(".env.example");

const queries = [...sql.matchAll(/(?:^with expected\(|^select cls\.relname|^select e\.id|^select tc\.table_name)[\s\S]*?;\n/gm)];
assert.equal(queries.length,5,"Preflight must contain exactly 5 read-only SELECT queries");
const cleaned = sql.replace(/--[^\n]*/g,"").replace(/'(?:''|[^'])*'/g,"''");
assert.doesNotMatch(cleaned,/^\s*(?:create|alter|drop|truncate|delete|insert|update|grant|revoke|execute|call|do|begin|commit|rollback|copy|set)\b/im,
 "Gate79 MUST be catalog read-only, even if executed against production");
for(const q of queries) assert.match(q[0],/;\s*$/,"Every query should terminate safely");
for(const s of [
  "information_schema.columns","information_schema.table_constraints",
  "pg_policies","pg_class","to_regclass","to_regprocedure",
  "public.onexa_post_journal(uuid,text,text,integer,text,jsonb,date,text,text,text,jsonb)",
  "onexa_private.guard_approval_posting()",
  "public.onexa_post_project_cost(uuid,text)",
  "public.onexa_company_module_scopes",
  "public.onexa_operations_work_orders",
  "public.onexa_native_maintenance_unpaid_sources",
  "project_wip_or_expense","cost_source_or_clearing",
  "MISSING_REQUIRED_FINANCE_MAPPING",
  "PRESENCE_ONLY_NOT_APPROVED_FOR_DEPLOYMENT",
]) assert.ok(sql.includes(s),"Missing requirement "+s);
assert.match(docs,/\*\*23\*\*/);
assert.match(docs,/\*\*29\*\*/);
assert.match(docs,/Free-plan organization/);
assert.match(docs,/previewAuthStorage\.ts/);
assert.match(docs,/No accounts, GL journals, mappings, policies, users or business data were created/);
assert.equal(pkg.scripts["check:gate79-staging-compatibility"],
 "node scripts/check-gate79-staging-compatibility.mjs");
assert.match(pkg.scripts.verify,/check:gate79-staging-compatibility/);
for (const required of [
  "onexa_accounting_inbox.approval_instance_id",
  "onexa_accounting_inbox.posting_step_name",
  "onexa_accounting_inbox.can_current_user_post",
  "supabase/manual-packages/gate64_approval_posting_bridge.sql",
]) assert.ok(checker.includes(required),"Missing guarded Gate64 view column: "+required);
assert.match(checker,/pendingViewColumns\.has\(key\)/);
assert.match(flags,/ONEXA_APPROVAL_POSTING_ENABLED\s*=\s*ONEXA_POSTING_ENABLED/);
assert.match(env,/VITE_ENABLE_ONEXA_APPROVAL_POSTING=""/);
assert.match(inbox,/if \(!ONEXA_APPROVAL_POSTING_ENABLED\)/);
assert.match(inbox,/approval_instance_id: null/);
assert.match(inbox,/posting_step_name: null/);
assert.match(inbox,/can_current_user_post: false/);
assert.match(inbox,/\.select\("id,legal_entity_id,branch_id,module_key,document_type,document_number,document_date,accounting_date,currency,party_name_snapshot,gross_total,approved_by,approved_at,revision"\)/);
console.log("Gate79 catalog-only ONEXA staging readiness contract passed");
