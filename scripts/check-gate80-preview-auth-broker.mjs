#!/usr/bin/env node
/**
 * Gate80 regression checks for Lovable-generated session broker.
 * Uses TypeScript transpilation and a synthetic window/postMessage/localStorage,
 * never a real auth token, Supabase project, browser account or network call.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import ts from "typescript";

const SOURCE = readFileSync(
  new URL("../src/integrations/supabase/previewAuthStorage.ts",import.meta.url),
  "utf8",
);
const compiled = ts.transpileModule(SOURCE,{
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;

const FAKE_ID = "a1111111-1111-4111-8111-111111111111";
const PREVIEW = `id-preview--${FAKE_ID}.lovableproject.com`;
const EDITOR = "https://lovable.dev";
const BAD_ORIGIN = "https://untrusted-embedder.example";

function mockStorage(seed = {}) {
  const values = new Map(Object.entries(seed));
  return {
    values,
    getItem(key) { return values.has(key) ? values.get(key) : null; },
    setItem(key,value) { values.set(key,String(value)); },
    removeItem(key) { values.delete(key); },
  };
}

function sessionEnvironment({host=PREVIEW,framed=true,ancestor=EDITOR,
  seed={},getResponse="sample-synthetic-session",setResponse=null}) {
  const localStorage=mockStorage(seed);
  const messages=[];
  const listeners=new Set();
  const win={
    addEventListener(kind,fn){ if(kind==="message") listeners.add(fn); },
    removeEventListener(kind,fn){ if(kind==="message") listeners.delete(fn); },
  };
  const parent={
    postMessage(message,targetOrigin){
      messages.push({message,targetOrigin});
      // Mimic browser targetOrigin security: a hostile parent does not see the
      // posted message and cannot respond as the trusted editor.
      if(targetOrigin!==ancestor) return;
      let value;
      if(message.type==="lovable-preview-auth:get") value=getResponse;
      else if(message.type==="lovable-preview-auth:set") value=setResponse;
      else if(message.type==="lovable-preview-auth:remove") value=null;
      else throw new Error("Unknown preview auth broker action");
      queueMicrotask(()=>{
        for(const listener of [...listeners]) listener({
          origin:ancestor,
          data: { type:"lovable-preview-auth:result",requestId:message.requestId,ok:true,value },
        });
      });
    },
  };
  win.parent=framed?parent:win;
  const exports={};
  runInNewContext(compiled,{
    exports,
    window:win,
    localStorage,
    location:{ hostname:host, ancestorOrigins:[ancestor] },
    document:{ referrer:ancestor+"/editor" },
    URL,
    Math,
    Date,
    Promise,
    setTimeout: (fn,ms) => setTimeout(fn,Math.min(ms,30)),
    clearTimeout,
    queueMicrotask,
  },{filename:"previewAuthStorage.transpiled.js",timeout:5000});
  return {store:exports.brokeredPreviewStorage(),localStorage,messages,listeners};
}

const serverExports={};
runInNewContext(compiled,{
  exports:serverExports,Math,Date,Promise,URL,setTimeout,clearTimeout,window:undefined,
});
assert.equal(serverExports.brokeredPreviewStorage(),undefined,
  "Server-side rendering must never touch browser auth storage");

const outside=sessionEnvironment({host:"onexa.example",seed:{"sb-session":"local-production-session"}});
assert.equal(outside.store,outside.localStorage,
  "Custom domain auth should use its own local storage, never preview editor messaging");
assert.equal(outside.store.getItem("sb-session"),"local-production-session");
assert.equal(outside.messages.length,0);

const forged=sessionEnvironment({
  host:"preview--other-project.lovableproject.com",
  seed:{"sb-session":"local-only"},
});
assert.equal(forged.store,forged.localStorage,
  "An untrusted user-name preview prefix must not select a broker project");
assert.equal(forged.messages.length,0);

const unframed=sessionEnvironment({framed:false});
assert.equal(unframed.store,unframed.localStorage,
  "Broker may only run in a true editor iframe");
assert.equal(unframed.messages.length,0);

const valid=sessionEnvironment({});
assert.notEqual(valid.store,valid.localStorage,"Trusted preview must use broker");
const incoming=await valid.store.getItem("sb-session");
assert.equal(incoming,"sample-synthetic-session");
assert.equal(valid.localStorage.getItem("sb-session"),incoming,
  "Session received from the editor must seed a previously empty preview origin");
assert.equal(valid.messages[0].targetOrigin,EDITOR,"Never broadcast a session via wildcard postMessage");
assert.equal(valid.messages[0].message.type,"lovable-preview-auth:get");
assert.equal(valid.messages[0].message.projectId,FAKE_ID);
assert.equal(valid.messages[0].message.key,"sb-session");
assert.equal(valid.messages[0].message.value,undefined);

await valid.store.setItem("sb-session","a-new-synthetic-session");
assert.equal(valid.localStorage.getItem("sb-session"),"a-new-synthetic-session");
assert.equal(valid.messages[1].message.type,"lovable-preview-auth:set");
assert.equal(valid.messages[1].message.value,"a-new-synthetic-session");
assert.equal(valid.messages[1].targetOrigin,EDITOR);
await valid.store.removeItem("sb-session");
assert.equal(valid.localStorage.getItem("sb-session"),null);
assert.equal(valid.messages[2].message.type,"lovable-preview-auth:remove");
assert.equal(valid.messages[2].message.value,"a-new-synthetic-session");
assert.equal(valid.messages[2].targetOrigin,EDITOR);
assert.equal(valid.listeners.size,0,"All async message handlers must be removed");

const loggedOut=sessionEnvironment({
  seed:{"sb-session":"old-synthetic-session"},
  getResponse:"", // editor's explicit logout tombstone
});
assert.equal(await loggedOut.store.getItem("sb-session"),null);
assert.equal(loggedOut.localStorage.getItem("sb-session"),null,
  "Explicit logout tombstone must not resurrect a prior local session");
assert.equal(loggedOut.messages[0].message.value,"old-synthetic-session");

const hostile=sessionEnvironment({
  ancestor:BAD_ORIGIN,
  host:PREVIEW,
  seed:{"sb-session":"local-synthetic-session"},
});
assert.notEqual(hostile.store,hostile.localStorage);
const pending=hostile.store.getItem("sb-session");
assert.ok(hostile.messages.length>=1);
assert.ok(hostile.messages.every(x=>x.targetOrigin===EDITOR),
  "Untrusted parent must never be passed as postMessage targetOrigin");
assert.ok(hostile.messages.every(x=>x.targetOrigin!==BAD_ORIGIN));
assert.equal(await pending,"local-synthetic-session",
  "Untrusted embedding must not overwrite the preview's local token");
assert.equal(hostile.listeners.size,0);

console.log("Gate80 preview auth broker: SSR, domain boundaries, trusted origin, login, logout and hostile parent passed");
