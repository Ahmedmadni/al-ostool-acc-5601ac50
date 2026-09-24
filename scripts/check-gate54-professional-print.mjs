import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const shell = read("src/components/layout/app-shell.tsx");
const styles = read("src/styles.css");
const card = read("src/components/ui/card.tsx");
const connectivity = read("src/components/shared/connectivity-banner.tsx");

for (const pattern of [
  /data-print-root/,
  /print-document-header/,
  /print-document-meta/,
  /tenant\.label\.name/,
  /activeGroupLabel/,
]) assert.match(shell, pattern);

for (const pattern of [
  /@page \{/,
  /size: A4 portrait/,
  /print-color-adjust: exact/,
  /thead \{ display: table-header-group; \}/,
  /tr, th, td, img, svg \{ break-inside: avoid; \}/,
  /\[data-slot="card"\]/,
]) assert.match(styles, pattern);

assert.match(card, /data-slot="card"/);
assert.match(connectivity, /no-print sticky/);
assert.match(shell, /onexa-shell-pattern no-print/);

console.log("Gate 54 professional print checks passed");
