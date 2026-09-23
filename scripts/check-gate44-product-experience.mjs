import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const styles = read("src/styles.css");
const shell = read("src/components/layout/app-shell.tsx");
const root = read("src/routes/__root.tsx");
const card = read("src/components/ui/card.tsx");

const requirements = [
  [styles.includes("IBM Plex Sans Arabic"), "Arabic interface font token"],
  [styles.includes("--sidebar: #ffffff"), "light desktop sidebar"],
  [styles.includes("--sidebar-primary: #5755d9"), "calm indigo navigation accent"],
  [styles.includes(".onexa-shell-pattern"), "subtle branded shell pattern"],
  [shell.includes("onexa-kbd"), "search keyboard hint"],
  [shell.includes('md:me-[17rem]'), "RTL-aware desktop content offset"],
  [shell.includes('strokeWidth={1.8}'), "consistent line icon weight"],
  [root.includes("IBM+Plex+Sans+Arabic"), "font delivery link"],
  [card.includes("rounded-xl"), "unified card radius"],
];

const missing = requirements.filter(([ok]) => !ok).map(([, label]) => label);
if (missing.length) {
  console.error(`Gate 44 product experience checks failed:\n- ${missing.join("\n- ")}`);
  process.exit(1);
}

console.log("Gate 44 product experience checks passed");
