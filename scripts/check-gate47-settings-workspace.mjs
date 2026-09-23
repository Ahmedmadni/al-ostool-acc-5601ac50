import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const workspace = read("src/components/settings/settings-workspace.tsx");

for (const pattern of [
  /SettingsWorkspaceShell/,
  /SETTINGS_LINKS/,
  /إدارة بيئة ONEXA والصلاحيات/,
  /xl:sticky xl:top-24/,
  /strokeWidth=\{1\.8\}/,
]) assert.match(workspace, pattern);

for (const path of [
  "src/routes/_authenticated/settings/regional.tsx",
  "src/routes/_authenticated/settings/users.tsx",
  "src/routes/_authenticated/settings/approvals.tsx",
  "src/routes/_authenticated/settings/permissions.tsx",
  "src/routes/_authenticated/settings/permissions-dashboard.tsx",
]) {
  assert.match(read(path), /SettingsWorkspaceShell/);
}

console.log("Gate 47 settings workspace checks passed");
