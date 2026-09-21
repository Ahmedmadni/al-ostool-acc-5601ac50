import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const shell = read("src/components/layout/app-shell.tsx");
const launcher = read("src/routes/_authenticated/apps.tsx");
const catalogue = read("src/lib/erp-apps.ts");
const guide = read("docs/design/onexa-information-architecture.md");
const pkg = JSON.parse(read("package.json"));

for (const invariant of ["App launcher", "Current application", "activeGroup.links", "tenant.label.name", "tenant.label.plan"]) {
  assert.ok(shell.includes(invariant), `contextual shell invariant missing: ${invariant}`);
}
assert.ok(!shell.includes("nav-open-groups"), "legacy accordion navigation storage is still present");
assert.ok(!shell.includes("allGroups.map((group) => {\n            const Icon"), "all modules are still rendered as a long sidebar accordion");

for (const invariant of ["useI18n", "dir={dir}", "app.titleEn", "app.subtitleEn", "category.labelEn", "end-3"]) {
  assert.ok(launcher.includes(invariant), `bilingual launcher invariant missing: ${invariant}`);
}
for (const field of ["titleEn", "subtitleEn", "labelEn"]) {
  assert.ok(catalogue.includes(field), `bilingual application catalogue field missing: ${field}`);
}
for (const heading of ["Navigation model", "Global top bar", "App launcher rules", "Directionality", "Responsive behavior"]) {
  assert.ok(guide.includes(heading), `information-architecture guide missing: ${heading}`);
}

assert.equal(pkg.scripts["check:gate33-navigation"], "node scripts/check-gate33-navigation.mjs");
assert.ok(pkg.scripts.verify.includes("check:gate33-navigation"), "Gate 33 is missing from verify");

console.log("Gate 33 ONEXA navigation checks passed ✓");
