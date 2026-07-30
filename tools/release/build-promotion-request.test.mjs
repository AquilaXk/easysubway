import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const script = path.resolve("tools/release/build-promotion-request.mjs");
const sha = (value) => createHash("sha256").update(value).digest("hex");

test("exact candidate와 단일 environment 승인을 canonical promotion request로 발행한다", () => {
  const f = fixture(); try {
    const result = run(f); assert.equal(result.status, 0, result.stderr);
    const requestBytes = readFileSync(f.output); const request = JSON.parse(requestBytes);
    assert.deepEqual(request, {
      schemaVersion: 1, artifactKind: "datapack-promotion-request", candidate: f.component,
      compatibilityEvidenceSha256: sha(f.compatibilityBytes), requestedBy: "AquilaXk",
      approval: { workflowRunId: "123", environment: "datapack-promotion", reviewer: "AquilaXk", approvalEvidenceSha256: sha(f.approvalBytes) },
      contractVersion: "datapack-promotion-v1", issueRef: "AquilaXk/easysubway#2699",
    });
    assert.equal(readFileSync(f.output, "utf8"), `${JSON.stringify(request, null, 2)}\n`);
  } finally { f.cleanup(); }
});

test("symlink, inventory hash, approval shape, existing output을 fail closed한다", () => {
  for (const mutate of [
    (f) => { f.component.artifactInventorySha256 = "0".repeat(64); writeFileSync(f.componentPath, JSON.stringify(f.component)); },
    (f) => { writeFileSync(f.approvalPath, JSON.stringify([{ state: "approved", environments: [{ name: "datapack-promotion" }, { name: "other" }], user: { login: "AquilaXk" } }])); },
    (f) => { writeFileSync(f.output, "sentinel"); },
    (f) => { symlinkSync(f.compatibilityPath, `${f.compatibilityPath}.link`); f.compatibilityPath = `${f.compatibilityPath}.link`; },
  ]) { const f = fixture(); try { mutate(f); const prior=exists(f.output)?readFileSync(f.output,"utf8"):null; assert.notEqual(run(f).status, 0); if(prior===null)assert.equal(exists(f.output),false);else assert.equal(readFileSync(f.output,"utf8"),prior); } finally { f.cleanup(); } }
});

function fixture() { const root = mkdtempSync(path.join(os.tmpdir(), "promotion-build-")); const component = componentValue(); const inventory = { schemaVersion: 1, artifactKind: "datapack-candidate-inventory", entries: [] }; const componentPath = file(root,"component.json",JSON.stringify(component)); const inventoryPath=file(root,"inventory.json",JSON.stringify(inventory)); const compatibilityPath=file(root,"compatibility.json","compatibility"); const approvalPath=file(root,"approvals.json",JSON.stringify([{state:"approved",environments:[{name:"datapack-promotion"}],user:{login:"AquilaXk"}}])); return {root,component,componentPath,inventoryPath,compatibilityPath,compatibilityBytes:Buffer.from("compatibility"),approvalPath,approvalBytes:readFileSync(approvalPath),output:path.join(root,"request.json"),cleanup:()=>rmSync(root,{recursive:true,force:true})}; }
function componentValue() { const inventoryBytes=Buffer.from(JSON.stringify({schemaVersion:1,artifactKind:"datapack-candidate-inventory",entries:[]})); return {schemaVersion:1,component:"data",repository:"AquilaXk/easysubway",gitSha:"a".repeat(40),workflowRunId:"123",dataVersion:"1",releaseSequence:1,manifestSha256:"b".repeat(64),provenance:{sourceSnapshotSetHash:"c".repeat(64)},artifactInventorySha256:sha(inventoryBytes),contractVersion:"datapack-contract-v3",issueRef:"AquilaXk/easysubway#2699"}; }
function file(root,name,value){const p=path.join(root,name);writeFileSync(p,value);return p;} function exists(p){try{readFileSync(p);return true;}catch{return false;}}
function run(f){return spawnSync(process.execPath,[script,"--component",f.componentPath,"--inventory",f.inventoryPath,"--compatibility-evidence",f.compatibilityPath,"--requested-by","AquilaXk","--approval-evidence",f.approvalPath,"--workflow-run-id","123","--issue-ref","AquilaXk/easysubway#2699","--output",f.output],{encoding:"utf8"});}
