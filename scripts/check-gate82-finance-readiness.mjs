import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (path) => readFileSync(new URL('../' + path, import.meta.url), 'utf8');
const sql = read('supabase/manual-packages/gate82_finance_posting_readiness_readonly.sql');
const cleaned = sql.replace(/--[^\n]*/g, '').replace(/'(?:''|[^'])*'/g, "''");
assert.equal((cleaned.match(/\bWITH\s+required\s*\(/gi) ?? []).length, 3);
assert.equal((cleaned.match(/;\s*(?:\n|$)/g) ?? []).length, 4);
assert.doesNotMatch(cleaned, /\b(?:insert|update|delete|create|alter|drop|truncate|grant|revoke|execute|call|do|begin|commit|copy|vacuum|refresh|select\s+.*\s+into)\b/i);
for (const signature of [
  'onexa_post_sales_invoice', 'onexa_post_purchase_invoice',
  'onexa_post_customer_receipt', 'onexa_post_supplier_payment',
  'onexa_post_bank_transfer', 'onexa_post_project_cost',
  'onexa_post_fleet_trip_cost', 'guard_approval_posting',
  'finalize_approval_posting', 'onexa_can_post_business_document'
]) assert.ok(sql.includes(signature), 'Missing required posting engine: '+signature);
assert.match(sql, /pg_catalog\.pg_policies/);
assert.match(sql, /information_schema\.columns/);
assert.match(sql, /FUNCTION_PRESENCE_ONLY_NOT_DEPLOYMENT_APPROVAL/);
console.log('Gate 82: finance posting SELECT-only catalog diagnostic verified.');
