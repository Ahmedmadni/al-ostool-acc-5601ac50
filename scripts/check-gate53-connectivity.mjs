import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");
const banner = read("src/components/shared/connectivity-banner.tsx");
const shell = read("src/components/layout/app-shell.tsx");

for (const pattern of [
  /navigator\.onLine/,
  /window\.addEventListener\("offline"/,
  /window\.addEventListener\("online"/,
  /queryClient\.refetchQueries\({ type: "active" }\)/,
  /role="status"/,
  /aria-live={restored \? "polite" : "assertive"}/,
  /data-connectivity={state}/,
  /تجنب ترحيل أو اعتماد العمليات/,
  /Avoid posting or approving transactions/,
]) assert.match(banner, pattern);

assert.match(shell, /<ConnectivityBanner \/>/);
assert.match(shell, /import { ConnectivityBanner }/);

console.log("Gate 53 connectivity safety checks passed");
