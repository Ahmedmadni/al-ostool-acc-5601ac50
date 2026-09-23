import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const shell = read("src/components/layout/app-shell.tsx");
const command = read("src/components/ui/command.tsx");
const styles = read("src/styles.css");

for (const pattern of [
  /href="#main-content"/,
  /تخطي إلى المحتوى الرئيسي/,
  /id="main-content"/,
  /tabIndex={-1}/,
  /requestAnimationFrame/,
  /\.focus\({ preventScroll: true }\)/,
  /title={lang === "en" \? "Global navigation search"/,
]) assert.match(shell, pattern);

for (const pattern of [
  /DialogTitle className="sr-only"/,
  /DialogDescription className="sr-only"/,
  /type CommandDialogProps/,
  /"me-2 h-4 w-4/,
  /cn\("ms-auto text-xs/,
]) assert.match(command, pattern);

assert.match(styles, /\.onexa-skip-link:focus-visible/);
assert.match(styles, /@media \(prefers-reduced-motion: reduce\)/);
assert.match(styles, /animation-duration: 0\.01ms !important/);

console.log("Gate 52 accessibility foundation checks passed");
