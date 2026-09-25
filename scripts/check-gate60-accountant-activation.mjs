import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const migrationPath =
  "supabase/manual-packages/gate60_workspace_accountant_activation.sql";
const postcheckPath =
  "supabase/manual-packages/gate60_workspace_accountant_activation_postcheck.sql";

for (const path of [migrationPath, postcheckPath]) {
  assert.ok(existsSync(path), `Gate 60 file missing: ${path}`);
}

const sql = read(migrationPath);
const postcheck = read(postcheckPath);
const server = read(
  "src/lib/provisioning/workspace-accountant.functions.ts",
);
const users = read("src/routes/_authenticated/settings/users.tsx");
const flags = read("src/lib/runtime-flags.ts");
const env = read(".env.example");
const smoke = read(
  "supabase/manual-packages/gate58_manual_journal_smoke_test_rollback.sql",
);
const pkg = JSON.parse(read("package.json"));

for (const marker of [
  "create or replace function public.handle_new_user()",
  "new.raw_app_meta_data->>'onexa_tenant_id'",
  "insert into public.profiles",
  "tenant_id",
  "create or replace function public.onexa_activate_accountant_user(",
  "ONEXA_WORKSPACE_OWNER_REQUIRED",
  "ONEXA_WORKSPACE_SEAT_LIMIT_REACHED",
  "ONEXA_TARGET_BELONGS_TO_ANOTHER_WORKSPACE",
  "pg_advisory_xact_lock",
  "'accountant'::public.app_role",
]) {
  assert.ok(sql.includes(marker), `Gate 60 SQL marker missing: ${marker}`);
}

assert.ok(
  sql.includes(
    "revoke all on function public.onexa_activate_accountant_user(uuid)",
  ),
  "activation RPC must not expose PUBLIC/anon execution",
);
assert.ok(
  postcheck.includes("authenticated_can_execute") &&
    postcheck.includes("anon_can_execute"),
  "Gate 60 function privilege postcheck missing",
);
assert.ok(
  postcheck.includes("'auth.users'::regclass"),
  "Gate 60 auth trigger postcheck missing",
);

for (const marker of [
  "requireSupabaseAuth",
  "supabaseAdmin.auth.admin.createUser",
  "app_metadata:",
  "onexa_tenant_id",
  '.rpc("onexa_activate_accountant_user"',
  "deleteUser(newUserId)",
  "employeeLookup",
  "الرقم الوظيفي مستخدم بالفعل",
]) {
  assert.ok(
    server.includes(marker),
    `accountant provisioning marker missing: ${marker}`,
  );
}

assert.ok(
  users.includes("ONEXA_WORKSPACE_ACCOUNTANT_ACTIVATION_ENABLED"),
  "users UI activation flag missing",
);
assert.ok(
  users.includes("createWorkspaceAccountantByOwner"),
  "users UI controlled accountant flow missing",
);
assert.ok(
  users.includes('type="password" minLength={8}'),
  "users UI strong temporary password requirement missing",
);
assert.ok(
  flags.includes("VITE_ENABLE_ONEXA_WORKSPACE_ACCOUNTANT_ACTIVATION"),
  "accountant activation runtime flag missing",
);
assert.ok(
  env.includes('VITE_ENABLE_ONEXA_WORKSPACE_ACCOUNTANT_ACTIVATION=""'),
  "accountant activation must default false",
);
assert.match(
  smoke,
  /when 'accountant' then 1[\s\S]*when 'finance_manager' then 1/,
  "Gate 58 smoke must prefer accountant creator and finance approver",
);

assert.equal(
  pkg.scripts["check:gate60-accountant-activation"],
  "node scripts/check-gate60-accountant-activation.mjs",
);
assert.ok(
  pkg.scripts.verify.includes("check:gate60-accountant-activation"),
  "Gate 60 is missing from verify",
);

console.log("Gate 60 tenant-safe accountant activation checks passed ✓");
