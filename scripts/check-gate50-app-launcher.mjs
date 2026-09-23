import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const launcher = readFileSync(new URL("../src/routes/_authenticated/apps.tsx", import.meta.url), "utf8");

for (const pattern of [
  /activeCategory/,
  /availableCategories/,
  /aria-pressed={activeCategory === "all"}/,
  /role="group"/,
  /allowed\.filter\(\(app\) => favorites\.includes\(app\.key\)\)\.length/,
  /setActiveCategory\("all"\)/,
  /حوكمة مساحة العمل والتكامل المحاسبي/,
  /Workspace governance & accounting integration/,
  /<AccountingIntegrationOverview \/>/,
  /<WorkspaceSubscriptionPanel \/>/,
]) assert.match(launcher, pattern);

const governancePosition = launcher.indexOf("<AccountingIntegrationOverview />");
const categoryPosition = launcher.indexOf("availableCategories.map((category)");
assert.ok(governancePosition > categoryPosition, "governance panels should follow the primary app-launcher workflow");
assert.match(launcher, /tenant\.canUseModule\(app\.subscriptionModule\)/);
assert.match(launcher, /can\(app\.permissionModule, "view"\)/);

console.log("Gate 50 app launcher workspace checks passed");
