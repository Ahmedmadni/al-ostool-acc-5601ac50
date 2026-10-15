import assert from "node:assert/strict";
import {readFileSync} from "node:fs";
const read=(p)=>readFileSync(new URL(`../${p}`,import.meta.url),"utf8");
const sql=read("supabase/manual-packages/gate43_fleet_trip_costs.sql");
const mapping=read("supabase/manual-packages/gate43_aoa_fleet_trip_mapping.sql");
const check=read("supabase/manual-packages/gate43_postcheck.sql");
const smoke=read("supabase/manual-packages/gate43_fleet_trip_smoke_test_rollback.sql");
const service=read("src/lib/fleet/fleet-trip-cost-service.ts");
const flags=read("src/lib/runtime-flags.ts");
const route=read("src/routes/_authenticated/fleet/trips/index.tsx");
for(const p of [
  /onexa_post_journal\(/,/onexa_post_fleet_trip_cost\(/,
  /claim_tenant_id\(\)/,/has_module_action\(_actor,'logistics','post'\)/,
  /_document\.created_by=_actor/,/status::text<>'completed'/,
  /_trip\.vehicle_id is distinct from _scope\.vehicle_id/,
  /source_kind' is distinct from 'unpaid_trip_charge'/,
  /unique \(tenant_id,legal_entity_id,external_reference\)/,
  /with \(security_invoker=true\)/,/enable row level security/g,
  /revoke all on public\.onexa_fleet_trip_scopes,public\.onexa_fleet_trip_cost_postings/,
  /category::text='liabilities'/,
]) assert.match(sql,p);
assert.match(mapping,/ONEXA_GATE43_CONFIRMED_TRIP_AND_ACCOUNTS_REQUIRED/);
assert.match(mapping,/REPLACE_UNPAID_TRIP_ACCRUAL_GL_CODE/);
assert.match(check,/direct_writes_denied/);
assert.match(check,/anon_can_execute/);
assert.match(smoke,/_retry:=public\.onexa_post_fleet_trip_cost/);
assert.match(smoke,/rollback;/i);
assert.match(service,/documentType:"fleet_trip_cost"/);
assert.match(flags,/ONEXA_FLEET_TRIP_COST_POSTING_ENABLED/);
assert.match(route,/OnexaFleetTripCostsPanel/);
assert.match(sql,/onexa_journal_headers j/);
assert.match(sql,/j\.state='posted' and j\.reversal_journal_id is null/);
assert.match(sql,/journal_reversed_or_missing/);
assert.match(sql,/journal_source_or_amount_mismatch/);
assert.match(sql,/trip_scope_mismatch/);
assert.match(sql,/ONEXA_FLEET_TRIP_JOURNAL_REVERSED_OR_MISSING/);
assert.match(sql,/j\.total_debit is distinct from d\.gross_total/);
assert.match(sql,/j\.total_credit is distinct from d\.gross_total/);
assert.match(check,/MAPPING_REQUIRED/);
assert.match(check,/journal_reversed_or_missing/);
const panel=read("src/components/fleet/onexa-fleet-trip-costs-panel.tsx");
assert.match(panel,/today\.getFullYear\(\)/);
assert.doesNotMatch(panel,/new Date\(\)\.toISOString\(\)\.slice\(0,10\)/);
console.log("Gate 43 fleet trip cost checks passed");
