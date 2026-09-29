import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";

// automerge-queue.yml의 review_gate jq 식을 그대로 추출해 실제 jq로 실행한다.
// 문자열 존재 여부가 아니라 리뷰 입력 → 게이트 판정 동작을 계약으로 고정한다 (#3006).
// #3008: 리뷰 경로를 Aquila Review로 통일해 claude[bot] Review는 더 이상 discovery로 인정하지 않는다.
const coordinator = readFileSync(new URL("../../.github/workflows/automerge-queue.yml", import.meta.url), "utf8");
const expression = coordinator.match(/review_gate=\$\(jq -r '([\s\S]*?)' <<<"\$\{reviews\}"\)/)?.[1];

const reviewGate = (pages) => execFileSync("jq", ["-r", expression], {
  input: JSON.stringify(pages),
  encoding: "utf8",
}).trim();

const CLAUDE = { login: "claude[bot]", id: 209825114, type: "Bot" };
const CODERABBIT = { login: "coderabbitai[bot]", id: 136622811, type: "Bot" };
const OWNER = { login: "AquilaXk", id: 1, type: "User" };
const MEMBER = { login: "reviewer", id: 2, type: "User" };

const review = (id, { state, user, association, body = "" }) => ({
  id,
  state,
  submitted_at: `2026-09-29T00:00:${String(id).padStart(2, "0")}Z`,
  author_association: association,
  user,
  body,
});
const claudeReview = (id, overrides = {}) => review(id, {
  state: "COMMENTED",
  user: CLAUDE,
  association: "NONE",
  ...overrides,
});
const ownerReview = (id, state, body = "") => review(id, { state, user: OWNER, association: "OWNER", body });
const memberReview = (id, state) => review(id, { state, user: MEMBER, association: "MEMBER" });

const AQUILA_FALLBACK_BODY = "**Actionable comments posted: 1**\n<!-- Review source: Aquila fallback; canonical visible structure: summary -->";
const AQUILA_UNIVERSAL_BODY = "**Actionable comments posted: 0**\n<!-- Review source: Aquila Universal Review; engine: aquila-review -->";
const CODEX_FALLBACK_BODY = "**Actionable comments posted: 2**\n<!-- Review source: Codex CLI fallback; canonical visible structure: summary -->";

test("automerge review_gate jq 식은 workflow 안에 inline으로 유지된다", () => {
  assert.ok(expression, "workflow must keep an inline review_gate jq expression");
  assert.doesNotMatch(expression, /claude/, "claude[bot] 신원 정의·인정 조건을 두지 않는다 (#3008)");
});

test("claude[bot] Review는 고정 신원이 일치해도 discovery로 인정하지 않는다 (#3008)", () => {
  assert.equal(reviewGate([[claudeReview(1)]]), "false", "빈 본문 claude[bot] COMMENTED");
  assert.equal(
    reviewGate([[claudeReview(1, { body: "🔴 0 · 🟡 0 · 🟣 0\n변경 범위를 검토했고 finding이 없습니다." })]]),
    "false",
    "개수 줄 요약이 있는 claude[bot] COMMENTED",
  );
  assert.equal(reviewGate([[claudeReview(1)], [ownerReview(2, "COMMENTED")]]), "false", "후속 페이지 사람 COMMENTED와 함께여도 거부");
  assert.equal(reviewGate([[claudeReview(1, { state: "APPROVED" })]]), "false", "claude[bot] APPROVED");
  assert.equal(
    reviewGate([[review(1, { state: "COMMENTED", user: { login: "claude", id: 77, type: "User" }, association: "COLLABORATOR" })]]),
    "false",
    "신뢰된 사람이 claude를 흉내 낸 마커 없는 COMMENTED",
  );
});

test("discovery 뒤 신뢰된 사람의 CHANGES_REQUESTED는 병합을 막는다", () => {
  const coderabbit = review(1, { state: "COMMENTED", user: CODERABBIT, association: "NONE" });
  assert.equal(
    reviewGate([[coderabbit, memberReview(2, "CHANGES_REQUESTED")]]),
    "false",
    "다른 reviewer의 active change request가 있으면 거부한다",
  );
  assert.equal(
    reviewGate([[coderabbit, ownerReview(2, "CHANGES_REQUESTED"), ownerReview(3, "COMMENTED")]]),
    "false",
    "후속 빈 COMMENTED가 change request를 지우지 않는다",
  );
  assert.equal(
    reviewGate([[coderabbit, memberReview(2, "CHANGES_REQUESTED"), memberReview(3, "APPROVED")]]),
    "true",
    "같은 reviewer의 이후 APPROVED는 자기 change request를 해제한다",
  );
});

test("기존 Aquila/Codex 마커 Review 경로는 그대로 인정된다 (회귀)", () => {
  assert.equal(reviewGate([[ownerReview(1, "COMMENTED", AQUILA_FALLBACK_BODY)]]), "true", "Aquila fallback 마커");
  assert.equal(reviewGate([[ownerReview(1, "COMMENTED", AQUILA_UNIVERSAL_BODY)]]), "true", "Aquila Universal Review 마커");
  assert.equal(reviewGate([[ownerReview(1, "COMMENTED", CODEX_FALLBACK_BODY)]]), "true", "Codex CLI fallback 마커");
  assert.equal(
    reviewGate([[ownerReview(1, "COMMENTED", "<!-- Review source: Aquila Universal Review; engine: aquila-review -->")]]),
    "false",
    "Actionable 머리말 없는 마커는 인정하지 않는다",
  );
  assert.equal(
    reviewGate([[ownerReview(1, "COMMENTED", AQUILA_FALLBACK_BODY), memberReview(2, "CHANGES_REQUESTED")]]),
    "false",
    "Aquila 마커 discovery도 active change request에 막힌다",
  );
});

test("기존 CodeRabbit·신뢰된 사람 APPROVED 동작은 그대로다 (회귀)", () => {
  const coderabbit = (id, user = CODERABBIT) => review(id, { state: "COMMENTED", user, association: "NONE" });
  assert.equal(reviewGate([[coderabbit(1)]]), "true", "고정된 CodeRabbit 신원");
  assert.equal(reviewGate([[coderabbit(1, { ...CODERABBIT, id: 999 })]]), "false", "위조된 CodeRabbit 신원");
  assert.equal(reviewGate([[memberReview(1, "APPROVED")]]), "true", "신뢰된 사람 APPROVED");
  assert.equal(reviewGate([[ownerReview(1, "COMMENTED")]]), "false", "마커 없는 사람 COMMENTED");
  assert.equal(reviewGate([]), "false", "빈 Review 목록");
});

test("게이트 계약 테스트는 Repository CI 계약 테스트 step에 등록된다", () => {
  const ci = readFileSync(new URL("../../.github/workflows/ci.yml", import.meta.url), "utf8");
  const run = ci.match(/- name: Repository CI \/ Run contract tests\n(?: {8}[^\n]*\n)*? {8}run: ([^\n]+)\n/)?.[1];
  assert.ok(run, "Repository CI / Run contract tests step의 run 명령이 필요하다");
  const files = run.split(/\s+/);
  assert.equal(files.slice(0, 2).join(" "), "node --test");
  assert.ok(files.includes("tools/ci/automerge-queue.test.mjs"), "tools/ci/automerge-queue.test.mjs가 Repository CI 계약 테스트 목록에 있어야 한다");
});
