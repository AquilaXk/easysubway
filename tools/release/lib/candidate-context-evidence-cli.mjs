// candidate-context(#2056 CANDIDATE) 기반 #2056 fragment producer들이 공유하는 최소
// CLI 진입점. --candidate-context/--output(필수)과 --repo-root/--provenance(선택)만
// 파싱해 build(...)를 호출하고 결과를 JSON으로 쓴다. 이 셋보다 인자가 더 필요한
// producer(예: build-planner-success-evidence.mjs의 --canary-result)는 대상이 아니다
// — 정확히 같은 4-인자 shape인 producer만 이 helper로 대체한다(SonarCloud PR #2357
// build-privacy-consistency-evidence.mjs ↔ build-mobile-consumption-evidence.mjs
// 17-line 중복 실측 결과에 대한 최소 공통화).

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

function argument(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index < 0 ? null : process.argv[index + 1];
}

// importMetaUrl은 호출한 producer 모듈의 import.meta.url이어야 한다(직접 실행 여부
// 판별). build는 { candidate, repoRoot, provenance }를 받아 evidence 객체를 반환하는
// producer의 buildXxxEvidence 함수를 그대로 넘긴다.
export function runCandidateContextEvidenceCli(importMetaUrl, build) {
  const entry = process.argv[1] ? path.resolve(process.argv[1]) : null;
  if (entry !== fileURLToPath(importMetaUrl)) return;

  const candidatePath = argument("candidate-context");
  const outputPath = argument("output");
  if (!candidatePath || !outputPath) {
    throw new Error("--candidate-context and --output are required");
  }
  const repoRootArg = argument("repo-root");
  const repoRoot = repoRootArg ? path.resolve(repoRootArg) : process.cwd();
  const provenance = argument("provenance") ?? "final-candidate";
  const evidence = build({
    candidate: JSON.parse(readFileSync(candidatePath, "utf8")),
    repoRoot,
    provenance,
  });
  mkdirSync(path.dirname(outputPath), { recursive: true });
  writeFileSync(outputPath, `${JSON.stringify(evidence, null, 2)}\n`);
}
