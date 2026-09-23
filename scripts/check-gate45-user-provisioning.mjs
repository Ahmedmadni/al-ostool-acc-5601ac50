import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const server = read("src/lib/admin-users.functions.ts");
const users = read("src/routes/_authenticated/settings/users.tsx");

for (const pattern of [
  /password: z\.string\(\)\.min\(8\)/,
  /employeeLookup/,
  /emailLookup/,
  /الرقم الوظيفي مستخدم بالفعل/,
  /authCreateErrorMessage/,
  /deleteUser\(newId\)/,
]) assert.match(server, pattern);

for (const pattern of [
  /createErrorMessages/,
  /type="password"/,
  /minLength=\{8\}/,
  /autoComplete="new-password"/,
]) assert.match(users, pattern);

console.log("Gate 45 user provisioning safety checks passed");
