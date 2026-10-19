import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql=readFileSync(new URL('../supabase/manual-packages/gate84_tenant_boundary_catalog_readonly.sql',import.meta.url),'utf8');
const stripped=sql.replace(/--[^\n]*/g,'').replace(/'(?:''|[^'])*'/g,"''");
assert.equal((stripped.match(/;\s*(?:\n|$)/g)??[]).length,3,'Exactly three catalog SELECTs required');
assert.doesNotMatch(stripped,/\b(?:insert|update|delete|create|alter|drop|truncate|grant|revoke|execute|call|do|begin|commit|copy|vacuum|refresh|set)\b/i);
assert.match(stripped,/pg_catalog\.pg_policies/);
assert.match(stripped,/pg_catalog\.pg_constraint/);
assert.match(stripped,/source_includes_tenant_id/);
assert.match(stripped,/RLS_DISABLED/);
assert.match(stripped,/MISSING_TABLE/);
assert.match(stripped,/INSPECT_EFFECTIVE_POLICIES/);
for(const table of ['onexa_business_documents','onexa_project_cost_postings','onexa_operations_work_orders','onexa_native_maintenance_unpaid_sources']) assert.ok(sql.includes(table),table);
console.log('Gate84: tenant isolation metadata audit remains three SELECT-only queries');
