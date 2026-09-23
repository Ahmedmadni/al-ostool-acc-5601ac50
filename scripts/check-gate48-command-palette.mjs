import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const shell = read("src/components/layout/app-shell.tsx");

for (const pattern of [
  /CommandDialog/,
  /CommandInput/,
  /CommandEmpty/,
  /CommandGroup/,
  /CommandItem/,
  /event\.metaKey \|\| event\.ctrlKey/,
  /event\.key\.toLowerCase\(\) === "k"/,
  /setCommandOpen\(\(open\) => !open\)/,
  /allGroups\.map/,
  /value=\{`\$\{link\.label\} \$\{link\.label_en\}/,
  /onSelect=\{\(\) => navigateFromCommand\(link\.to\)\}/,
  /لا توجد صفحة متاحة تطابق بحثك/,
  /No accessible page matches your search/,
]) assert.match(shell, pattern);

assert.doesNotMatch(shell, /import \{ Input \} from "@\/components\/ui\/input"/);
assert.ok((shell.match(/\{ to: "\//g) ?? []).length >= 40, "global search should expose the full navigation catalog");

console.log("Gate 48 command palette checks passed");
