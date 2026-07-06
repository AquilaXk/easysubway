import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { execFile } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import assert from "node:assert/strict";
import test from "node:test";

const execFileAsync = promisify(execFile);
const REPO_ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");

// 메모리 객체 저장소 mock: PUT 저장, HEAD/GET 응답. Cache-Control·meta-sha256 기록.
function startMockStorage() {
  const objects = new Map(); // key -> { body, sha256, cacheControl }
  const server = createServer((req, res) => {
    const key = decodeURIComponent(req.url.replace(/^\//, ""));
    if (req.method === "PUT") {
      const chunks = [];
      req.on("data", (c) => chunks.push(c));
      req.on("end", () => {
        const body = Buffer.concat(chunks);
        objects.set(key, {
          body,
          sha256: req.headers["opc-meta-sha256"],
          cacheControl: req.headers["cache-control"],
        });
        res.statusCode = 200;
        res.end();
      });
      return;
    }
    const found = objects.get(key);
    if (!found) { res.statusCode = 404; res.end(); return; }
    if (found.cacheControl) res.setHeader("cache-control", found.cacheControl);
    res.setHeader("content-length", String(found.body.length));
    res.statusCode = 200;
    res.end(req.method === "HEAD" ? undefined : found.body);
  });
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve({ server, objects, port: server.address().port }));
  });
}

async function runPublish(planPath, root, baseUrl) {
  return execFileAsync("node", [
    path.join(REPO_ROOT, "tools/datapack/publish-object-storage.mjs"),
    "--plan", planPath, "--root", root,
  ], { env: { ...process.env, EASYSUBWAY_OBJECT_STORAGE_PREAUTH_BASE_URL: baseUrl } });
}

test("게시 실행기는 동일 sha의 releases 객체 재게시를 멱등 skip하고 상이 sha는 거부한다", async () => {
  const mock = await startMockStorage();
  const workspace = await mkdtemp(path.join(tmpdir(), "publish-run-"));
  const baseUrl = `http://127.0.0.1:${mock.port}`;
  try {
    await mkdir(path.join(workspace, "catalog"), { recursive: true });
    const manifestBytes = Buffer.from(JSON.stringify({ ok: 1 }));
    await writeFile(path.join(workspace, "catalog", "current.json"), manifestBytes);
    const plan = {
      schemaVersion: 2,
      mode: "object-storage-preflight",
      manifestObjectKey: "catalog/current.json",
      steps: [
        { type: "put-release-manifest-object", sourcePath: "catalog/current.json",
          objectKey: "catalog/releases/5.json", sha256: sha256(manifestBytes),
          sizeBytes: manifestBytes.length, packCount: 1, immutable: true },
        { type: "verify-release-manifest-object", objectKey: "catalog/releases/5.json",
          sha256: sha256(manifestBytes), sizeBytes: manifestBytes.length, packCount: 1, immutable: true },
        { type: "put-manifest-object", sourcePath: "catalog/current.json",
          objectKey: "catalog/current.json", sha256: sha256(manifestBytes),
          sizeBytes: manifestBytes.length, packCount: 1 },
        { type: "verify-manifest-object", objectKey: "catalog/current.json",
          sha256: sha256(manifestBytes), sizeBytes: manifestBytes.length, packCount: 1 },
      ],
    };
    const planPath = path.join(workspace, "plan.json");
    await writeFile(planPath, JSON.stringify(plan));

    // 1회차: 정상 게시.
    await runPublish(planPath, workspace, baseUrl);
    assert.ok(mock.objects.has("catalog/releases/5.json"));

    // 2회차: 동일 바이트 재게시 → 멱등 성공(에러 없음).
    await runPublish(planPath, workspace, baseUrl);

    // 상이 바이트를 같은 seq로: releases/5.json에 다른 sha를 심어두고 재실행 → 거부.
    mock.objects.set("catalog/releases/5.json", { body: Buffer.from("different"), sha256: sha256(Buffer.from("different")), cacheControl: "public, max-age=31536000, immutable" });
    await assert.rejects(runPublish(planPath, workspace, baseUrl), /immutable violation/);
  } finally {
    mock.server.close();
    await rm(workspace, { recursive: true, force: true });
  }
});
