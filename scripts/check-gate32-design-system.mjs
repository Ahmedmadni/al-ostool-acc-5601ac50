import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";

const read = (path) => readFileSync(path, "utf8");
const component = read("src/components/brand/onexa-brand.tsx");
const publicLogo = read("src/components/public/brand-logo.tsx");
const shell = read("src/components/layout/app-shell.tsx");
const styles = read("src/styles.css");
const manifest = read("public/manifest.webmanifest");
const root = read("src/routes/__root.tsx");
const guide = read("docs/design/onexa-design-system.md");

for (const path of ["public/onexa-approved-logo.png", "public/onexa-logo-transparent.png", "public/onexa-mark-192.png", "public/onexa-mark-512.png", "public/onexa-og.png"]) {
  assert.ok(existsSync(path), `missing generated brand asset: ${path}`);
}

for (const token of ["OnexaBrandMark", "OnexaBrandLockup", "onexa-logo-transparent-user.png.asset.json"]) {
  assert.ok(component.includes(token), `canonical brand component missing: ${token}`);
}
assert.ok(statSync("public/onexa-logo-transparent.png").size > 0, "legacy transparent logo fallback is empty");
assert.ok(publicLogo.includes("OnexaBrandLockup"), "public header is not using the canonical ONEXA lockup");
assert.ok(shell.includes("OnexaBrandLockup"), "authenticated shell is not using the canonical ONEXA lockup");
assert.ok(!shell.includes('viewBox="0 0 40 40"'), "legacy inline shell logo is still present");

for (const token of ["--brand-ink", "--brand-blue", "--brand-cyan", "--brand-amber"]) {
  assert.ok(styles.includes(token), `design token missing: ${token}`);
}
const approvedDigest = createHash("sha256").update(readFileSync("public/onexa-approved-logo.png")).digest("hex");
assert.equal(approvedDigest, "0ec105935a2eb02289a107bdca5e7774aac69fc65e5011875271b046415f12d7", "approved ONEXA logo was altered");
assert.ok(!component.includes("<svg") && !component.includes("<path"), "the approved logo must not be redrawn in React");
assert.ok(manifest.includes('"theme_color": "#1D4ED8"'), "PWA theme color is stale");
assert.ok(root.includes('content: "#1D4ED8"'), "document theme color is stale");
for (const heading of ["Brand idea", "Color tokens", "Typography", "Accessibility", "Logo controls"]) {
  assert.ok(guide.includes(heading), `design-system guide missing: ${heading}`);
}

console.log("Gate 32 ONEXA design-system checks passed ✓");
