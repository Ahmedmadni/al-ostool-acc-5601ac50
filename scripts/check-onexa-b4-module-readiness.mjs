// Phase 11 ONEXA B4 source-to-GL module publishing manifest integrity.
// Pure local source/contract validation: no database, no deployments and no
// customer data. This NEVER marks a hosted finance module production-ready.
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const read = (path) => readFileSync(path,"utf8");
const manifestPath = process.argv[2] ?? "docs/runbooks/onexa-b4-module-publisher-manifest.json";
const inventory = JSON.parse(read(resolve(manifestPath)));
const modules = inventory.modules;
assert.equal(inventory.schema_version,1,"Unknown publisher inventory schema");
assert.equal(inventory.kind,"ONEXA_B4_PUBLISHING_MODULE_INVENTORY");
assert.equal(modules.length,14,"The accounting rollout needs fourteen distinct publishing RPCs");

const flags = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const contracts = read("src/lib/accounting/posting-contracts.ts");
const catalog = read("supabase/manual-packages/onexa_b4_module_publishers_READ_ONLY.sql");
const globalCatalog = read("supabase/manual-packages/onexa_b4_release_catalog_READ_ONLY.sql");
const postingAmounts = read("src/lib/accounting/posting-readiness.ts");
const seen = new Set();
const sourceTypes = new Set();

assert.ok(flags.includes("export const ONEXA_POSTING_ENABLED =") &&
 flags.includes('import.meta.env.VITE_ENABLE_ONEXA_POSTING === "true"') &&
 env.includes('VITE_ENABLE_ONEXA_POSTING=""'),
 "Global GL posting switch must remain disabled by default");

function functionBody(sql, rpc) {
  const names = [...sql.matchAll(/\bcreate(?:\s+or\s+replace)?\s+function\s+public\.(\w+)\s*\(/gi)];
  const matches = names.filter(match => match[1] === rpc);
  assert.equal(matches.length,1,"Expected exactly one SQL function definition for "+rpc);
  const begin = matches[0].index;
  const following = names.filter(match=>match.index>begin)
    .map(match=>match.index).sort((a,b)=>a-b)[0] ?? sql.length;
  const text = sql.slice(begin,following);
  // May contain trailing GRANT/COMMENT statements, but the posted GL call
  // must occur inside the function body, before the first matching delimiter.
  const delimiters = [...text.matchAll(/\$(?:[a-z_][a-z_0-9]*)?\$\s*;/gi)];
  const end = delimiters[0]?.index ?? -1;
  assert.ok(end>0,"Missing SQL function body closing delimiter: "+rpc);
  return text.slice(0,end+delimiters[0][0].length);
}

for (const mod of modules) {
  assert.ok(typeof mod.id==="string" && /^[a-z][a-z0-9_]*$/.test(mod.id));
  assert.match(mod.gate,/^g(?:35|36|37|38|39|40|41|42|43|58|65|66|67)$/);
  assert.match(mod.rpc,/^onexa_post_[a-z0-9_]+$/);
  assert.match(mod.flag,/^ONEXA_[A-Z0-9_]+_ENABLED$/);
  assert.match(mod.env,/^VITE_ENABLE_ONEXA_[A-Z0-9_]+$/);
  assert.ok(!seen.has(mod.rpc),"Duplicate publisher RPC: "+mod.rpc);
  seen.add(mod.rpc);
  assert.ok(mod.sql.startsWith("supabase/manual-packages/") && mod.sql.endsWith(".sql"),
    "Publishers must use a versioned manual package: "+mod.rpc);
  assert.ok(mod.client.startsWith("src/lib/") && mod.client.endsWith(".ts"),
    "Publishers must have source-controlled client service: "+mod.rpc);
  assert.ok(mod.source_types.length>=1 && mod.source_types.length<=2);
  const sql = read(mod.sql);
  const service = read(mod.client);
  const flagUsage = read(mod.flag_usage ?? mod.client);
  const fn = functionBody(sql,mod.rpc);

  assert.ok(fn.includes("onexa_post_journal("),
    "Publisher must actually call B4 inside RPC (not just SQL preflight): "+mod.rpc);
  assert.ok(fn.includes("has_module_action"),
    "Publisher must check finance module-level permissions: "+mod.rpc);
  assert.ok(fn.includes("ONEXA_POST_JOURNAL_INVALID_RESPONSE"),
    "Publisher must fail closed on empty B4 journal response: "+mod.rpc);
  assert.ok(service.includes('"' + mod.rpc + '"') && service.includes(".rpc("),
    "Client must call expected server RPC rather than direct B4: "+mod.rpc);
  assert.ok(flagUsage.includes(mod.flag),
    "The owning service or manual-journal panel must check the module flag: "+mod.rpc);
  assert.ok(flags.includes("export const "+mod.flag+" =") &&
    flags.includes("import.meta.env."+mod.env+' === "true"'),
    "Runtime must expose exact opt-in flag: "+mod.env);
  assert.ok(env.includes(mod.env+'=""'),
    "No module may be enabled by default in .env.example: "+mod.env);

  for (const sourceType of mod.source_types) {
    assert.match(sourceType,/^[a-z_]+$/);
    assert.ok(sql.includes("'"+sourceType+"'"),
      "Expected source type not present in publisher SQL: "+mod.rpc+" / "+sourceType);
    assert.ok(!sourceTypes.has(sourceType),
      "Source type assigned to multiple publishing RPCs: "+sourceType);
    sourceTypes.add(sourceType);
  }
  assert.ok(catalog.includes("'"+mod.id+"','"+mod.gate+"','"+mod.rpc+"'"),
    "Read-only installed-function catalog out of sync with manifest: "+mod.rpc);
  for (const sourceType of mod.source_types) {
    assert.ok(catalog.includes("'"+sourceType+"'"),
      "Read-only installed-function catalog omitted expected GL source type: "+sourceType);
  }
}

// The two contract types below do not currently have standalone publishing RPCs;
// reporting them as live supported modules would be misleading.
assert.deepEqual(
 inventory.not_separate_rpc_publishers.map(x=>x.source_type).sort(),
 ["fixed_asset_acquisition","fuel_issue"].sort(),
 "An unimplemented finance source must never be silently shown as ready");
for (const src of inventory.not_separate_rpc_publishers) {
  assert.ok(!sourceTypes.has(src.source_type),
    "Non-standalone source must not claim a second posting writer: "+src.source_type);
  assert.ok(contracts.includes('"'+src.source_type+'"'),
    "Unimplemented source must be documented in the reporting contract");
}

const sourceTypeSection=contracts.slice(
  contracts.indexOf("export type SourceDocumentType ="),
  contracts.indexOf("export type DocumentStatus ="),
);
const inContract = [...sourceTypeSection.matchAll(/^\s*\|\s*"([a-z_]+)"/gm)].map(m=>m[1]);
for (const src of inContract) {
  assert.ok(sourceTypes.has(src) ||
    inventory.not_separate_rpc_publishers.some(x=>x.source_type===src),
    "Contract source has no publisher or explicit gap: "+src);
}
assert.ok(sourceTypes.has("manual_journal") &&
  !contracts.includes('documentType: "manual_journal"'),
  "Manual journal must stay a separate governed Gate58 workflow, not a fake document contract");

assert.ok(catalog.includes("has_function_privilege('authenticated'") &&
  catalog.includes("ONEXA_POST_JOURNAL_INVALID_RESPONSE") &&
  catalog.includes("'SOURCE_TYPE_BLOCKED'") &&
  catalog.includes("'SOURCE_PRESENT_ONLY_STAGING_REQUIRED'"),
  "Read-only catalog must distinguish function/source readiness from real E2E acceptance");
for (const gate of ["GL_MANUAL_SOURCE_ALLOWED","GL_HEADER_EXACTLY_BALANCED",
  "B4_STRICT_MONEY_CHECKS","B4_POST_RETRY_CONTENT_GUARD",
  "B4_REVERSE_RETRY_CONTENT_GUARD"]) {
  assert.ok(globalCatalog.includes(gate),
    "Global B4 release blockers cannot be bypassed by module-level status: "+gate);
}
for (const file of [catalog,globalCatalog]) {
  const noComments=file.replace(/^--.*$/gm,"");
  const unquoted=noComments.replace(/'(?:''|[^'])*'/g,"''");
  assert.match(unquoted,/^\s*with\b/i,"Catalog must be SELECT-only CTE");
  assert.doesNotMatch(unquoted,/\b(?:INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|GRANT|REVOKE|TRUNCATE|EXECUTE|COPY|DO|CALL)\b/i,
    "Production catalog must not allow SQL mutations");
  assert.equal((unquoted.match(/;/g)??[]).length,1,
    "Catalog must be a single SELECT-only statement");
}
assert.ok(!postingAmounts.includes("Math.abs(draft.totalDebit - draft.totalCredit) > 0.005"),
  "UI must not claim a financially unbalanced B4 posting is ready");
console.log("ONEXA B4 module source contracts passed: "+modules.length+
  " publishers / "+sourceTypes.size+" GL source types (not production readiness) ✓");
