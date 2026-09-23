import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const layout = read("src/routes/_authenticated/settings.tsx");
const overview = read("src/routes/_authenticated/settings/index.tsx");
const shell = read("src/components/layout/app-shell.tsx");

for (const pattern of [
  /SettingsWorkspace/,
  /<Outlet \/>/,
  /SETTINGS_LINKS/,
  /إدارة بيئة ONEXA والصلاحيات/,
  /xl:sticky xl:top-24/,
  /strokeWidth=\{1\.8\}/,
]) assert.match(layout, pattern);

for (const pattern of [
  /SettingsOverview/,
  /مركز إعدادات ONEXA/,
  /SECTIONS/,
  /إعدادات واضحة وآمنة/,
]) assert.match(overview, pattern);

assert.match(shell, /to: "\/settings", label: "نظرة عامة على الإعدادات"/);
console.log("Gate 47 settings workspace checks passed");
