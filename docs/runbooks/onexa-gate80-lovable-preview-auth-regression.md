# Gate 80 — Lovable preview auth broker regression

The Lovable security update at commit `e3562c204c2fdedfbee24bb70c4b4be123bafd52` modified `src/integrations/supabase/previewAuthStorage.ts`, alongside the package lock, package manifest, generated DB types and route tree. The update is NOT package-only.

`scripts/check-gate80-preview-auth-broker.mjs` transpiles the existing **generated** TypeScript module and executes it inside a simulated browser environment, with synthetic V4 project IDs and synthetic session strings only. It checks:

- Server-side rendering never accesses browser storage and custom/non-preview domains use localStorage without cross-window messages.
- Forged `preview--name` hostnames do not impersonate a preview project's identity, and unframed preview pages do not broker sessions.
- A legitimate Lovable preview iframe sends auth requests only to the exact trusted editor `targetOrigin`, scopes them to the synthetic project ID, seeds a session, handles updates and sends the previous token during removal.
- An editor's empty-string logout tombstone clears the local session, preventing a stale-session resurrection.
- A hostile iframe parent is never used as the message target and cannot replace a local session through a forged editor response; pending listeners are removed on timeout.

The test uses Node's VM and TypeScript transpilation, with mocked localStorage, window events and postMessage. It does **not** use real authentication tokens, connect to Supabase, use Lovable production identities or change the generated source. It runs in `npm run verify` and therefore on every PR. Fake editor timers are bounded to keep CI fast.

## Important limitations

This provides a repeatable contract for the Lovable-generated preview broker; it does NOT certify complete cross-origin iframe browser behavior, login consent, cookies, CSP, actual token refresh, revocation across simultaneous windows or mobile/webview storage policies. Final acceptance requires interactive login/logout testing in a trusted Lovable preview, including blocked third-party storage, reload and multi-tab cases, before releasing a new production auth client.

**Staging status:** Supabase staging remains uncreated. User must identify which organization should own it and accept any disclosed nonzero project cost. The linked Supabase connector is not the same as Lovable's production Supabase instance. Never copy production customer data or keys to staging.
