// Pure source-only planner, never executes SQL or changes production flags.
// Fails on missing parents, circular order, mistagged legacy packages or a
// publisher not covered by a concrete source-controlled install gate.
import assert from "node:assert/strict";

const MANDATORY = {
  g36:["g35"],g39:["g35"],g40:["g36"],g63:["g62"],
  g64:["g63","g35","g36","g39","g40","g41","g42","g43"],
  g65:["g35","g64"],g67:["g64"],g66:["g42","g64"],
};
export function validateFinanceDependencyPlan(manifest,publishers) {
  assert.equal(manifest.schema_version,1);
  assert.equal(manifest.purpose,"NON-EXECUTING dependency/order evidence; never a SQL installer");
  assert.equal(manifest.nodes.length,17,"17 nodes required: B4, approval foundations and 14 publishing gates");
  const nodes=new Map();
  for(const n of manifest.nodes){
    assert.match(n.id,/^(?:b4|g\d+)$/);
    assert.ok(!nodes.has(n.id),"Duplicated install node: "+n.id);
    assert.ok(Number.isInteger(n.wave)&&n.wave>=0,"Invalid stage for "+n.id);
    assert.ok(Array.isArray(n.depends_on)&&Array.isArray(n.requires),"Invalid dependency metadata for "+n.id);
    assert.ok(["foundation","publisher"].includes(n.kind));
    assert.ok(["foundation","standard","manual_journal_source_fix","strict_posting_bridge",
      "legacy_real_estate_review","saas_forbidden_legacy_engine",
      "payroll_gate7_8_compatibility_review"].includes(n.policy));
    if(n.id==="b4") assert.equal(n.package,null);
    else assert.match(n.package,/^supabase\/manual-packages\/[a-zA-Z0-9_]+\.sql$/);
    assert.ok(n.requires.length>0,"No preflight metadata for "+n.id);
    const seen=new Set();
    for(const r of [...n.requires,...(n.targets??[])]){
      assert.ok(["table","function","column","trigger"].includes(r.kind));
      assert.match(r.ref,/^(?:public|onexa_private)\.[A-Za-z0-9_]+/);
      const key=r.kind+":"+r.ref+":"+(r.column??r.name??"");
      assert.ok(!seen.has(key),"Duplicated probe "+n.id+" "+key);
      seen.add(key);
      if(r.kind==="column")assert.match(r.column,/^[a-z0-9_]+$/);
      if(r.kind==="trigger")assert.match(r.name,/^[a-z0-9_]+$/);
    }
    nodes.set(n.id,n);
  }
  assert.equal(nodes.get("b4").wave,0);
  for(const n of nodes.values()){
    const parents=new Set(n.depends_on);
    assert.equal(parents.size,n.depends_on.length,"Duplicated parent of "+n.id);
    for(const parentId of parents){
      const parent=nodes.get(parentId);
      assert.ok(parent,"Unknown required prerequisite "+parentId+" for "+n.id);
      assert.ok(parent.wave<n.wave,"Unsafe same/later wave "+parentId+" -> "+n.id);
    }
  }
  for(const [nodeId,parentIds] of Object.entries(MANDATORY)){
    const parents=nodes.get(nodeId)?.depends_on??[];
    for(const parent of parentIds) assert.ok(parents.includes(parent),
      "Mandatory finance ordering dependency removed: "+parent+" -> "+nodeId);
  }
  assert.equal(nodes.get("g37").policy,"payroll_gate7_8_compatibility_review",
    "Payroll cannot be installed until the distinct Gate7/8 foundation is reviewed in Staging");
  assert.equal(nodes.get("g66").policy,"saas_forbidden_legacy_engine",
    "The legacy Gate66 writer MUST NOT be installed in an ONEXA SaaS plane");
  assert.equal(nodes.get("g67").policy,"legacy_real_estate_review",
    "Legacy lease tables need independent tenancy/security review");
  assert.equal(nodes.get("g64").policy,"strict_posting_bridge");
  assert.equal(nodes.get("g58").policy,"manual_journal_source_fix");
  assert.deepEqual(nodes.get("g65").targets.map(x=>x.ref),["public.onexa_post_inventory_document(uuid,text)"]);
  const sourceModules=publishers.modules;
  assert.equal(sourceModules.length,14,"Unexpected number of B4 publishing modules");
  const assigned=new Map();
  for(const m of sourceModules){
    const node=nodes.get(m.gate);
    assert.ok(node&&node.kind==="publisher","Publisher has no installation gate: "+m.id);
    assert.equal(node.package,m.sql,"Install gate points to wrong SQL source: "+m.id);
    assert.ok(node.targets.some(x=>x.kind==="function" && x.ref.startsWith("public."+m.rpc+"(")),
      "Install gate does not probe the owning publisher RPC: "+m.rpc);
    assigned.set(node.id,(assigned.get(node.id)||0)+1);
  }
  for(const n of nodes.values())if(n.kind==="publisher"){
    assert.ok(assigned.has(n.id),"Orphan publisher installation gate: "+n.id);
  }
  // Do not hide legacy incompatibility with a valid topological order.
  const deployable=manifest.nodes.filter(n=>n.policy!=="saas_forbidden_legacy_engine");
  return {
    waves:[...new Set(deployable.map(n=>n.wave))].sort((a,b)=>a-b).map(wave=>({
      wave,nodes:deployable.filter(n=>n.wave===wave).map(n=>n.id),
    })),
    excluded_legacy_gate:"g66",
    node_count:manifest.nodes.length,
    publisher_count:sourceModules.length,
  };
}
