#!/usr/bin/env node
// Optional Staging-only network preflight; no secrets, mutations or database queries.
import { readFileSync } from 'node:fs';
import { audit } from './audit-staging-evidence.mjs';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

export function stagingTarget(manifest) {
  const verdict = audit(manifest);
  if (!verdict.ready) return { allowed: false, errors: verdict.errors };
  const production = new URL(manifest.production.supabase_url);
  const staging = new URL(manifest.staging.supabase_url);
  if (staging.origin === production.origin) return { allowed: false, errors: ['PRODUCTION_TARGET_BLOCKED'] };
  return { allowed: true, origin: staging.origin, errors: [] };
}

export async function probeStaging(manifest, fetcher = fetch) {
  const target = stagingTarget(manifest);
  if (!target.allowed) return { status: 'blocked', errors: target.errors };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 5000);
  try {
    // Health endpoint only; GET without API keys, cookies or Authorization.
    const response = await fetcher(target.origin + '/auth/v1/health', {
      method: 'GET', redirect: 'manual', credentials: 'omit', cache: 'no-store',
      signal: controller.signal, headers: { Accept: 'application/json' }
    });
    return { status: response.status >= 200 && response.status < 300 ? 'reachable' : 'unverified',
      http_status: response.status, note: 'HEALTH_ONLY_NO_TENANT_OR_DATABASE_VERIFICATION' };
  } catch {
    return { status: 'unreachable', note: 'STAGING_HEALTH_REQUEST_FAILED' };
  } finally { clearTimeout(timer); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (process.argv.length !== 4 || process.argv[3] !== '--staging-health-only')
      throw Error('Usage: node scripts/probe-staging-health.mjs manifest.json --staging-health-only');
    const m = JSON.parse(readFileSync(process.argv[2], 'utf8'));
    const result = await probeStaging(m);
    console.log(JSON.stringify(result, null, 2));
    if (result.status !== 'reachable') process.exitCode = 1;
  } catch (e) { console.error(e.message); process.exitCode = 2; }
}
