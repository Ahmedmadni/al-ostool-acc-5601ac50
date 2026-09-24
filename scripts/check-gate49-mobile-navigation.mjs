import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const shell = readFileSync(new URL("../src/components/layout/app-shell.tsx", import.meta.url), "utf8");

for (const pattern of [
  /const \[mobileNavOpen, setMobileNavOpen\] = useState\(false\)/,
  /<Sheet open=\{mobileNavOpen\} onOpenChange=\{setMobileNavOpen\}>/,
  /side=\{dir === "rtl" \? "right" : "left"\}/,
  /<ScrollArea className="h-\[calc\(100dvh-10\.5rem\)\]">/,
  /<SheetClose asChild>/,
  /allGroups\.map\(\(group\) =>/,
  /setMobileNavOpen\(false\);[\s\S]*?\}, \[path\]\);/,
  /className="shrink-0 md:hidden"/,
  /className="shrink-0 sm:hidden"/,
  /فتح قائمة التنقل/,
  /Application navigation/,
]) assert.match(shell, pattern);

assert.match(shell, /tenant\.label\.name.*tenant\.label\.plan/);
assert.match(shell, /roles\.map\(\(r\) => roleLabel\[r\] \?\? r\)/);

console.log("Gate 49 mobile navigation checks passed");
