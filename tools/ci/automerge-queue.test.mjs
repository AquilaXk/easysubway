import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import test from "node:test";

// automerge-queue.yml의 review_gate jq 식을 그대로 추출해 실제 jq로 실행한다.
// 문자열 존재 여부가 아니라 리뷰 입력 → 게이트 판정 동작을 계약으로 고정한다 (#3006).
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
  assert.match(expression, /def is_claude:/);
});

test("고정된 claude[bot] 신원의 COMMENTED Review는 본문 마커 없이 discovery로 인정된다", () => {
  assert.equal(reviewGate([[claudeReview(1)]]), "true", "inline comment wrapper(빈 본문) Review도 봇 신원으로 인정한다");
  assert.equal(
    reviewGate([[claudeReview(1, { body: "🔴 0 · 🟡 0 · 🟣 0\n변경 범위를 검토했고 finding이 없습니다." })]]),
    "true",
    "요약 본문이 있는 Claude Code Review도 인정한다",
  );
  assert.equal(
    reviewGate([[claudeReview(1)], [ownerReview(2, "COMMENTED")]]),
    "true",
    "후속 페이지의 빈 COMMENTED가 claude[bot] discovery를 지우지 않는다",
  );
});

test("claude[bot] 이름만 같거나 신원이 어긋난 Review는 discovery로 인정하지 않는다", () => {
  assert.equal(reviewGate([[claudeReview(1, { user: { ...CLAUDE, id: 999 } })]]), "false", "user.id가 다르면 거부한다");
  assert.equal(reviewGate([[claudeReview(1, { user: { ...CLAUDE, type: "User" } })]]), "false", "user.type이 Bot이 아니면 거부한다");
  assert.equal(
    reviewGate([[claudeReview(1, { user: { login: "claude", id: 209825114, type: "Bot" } })]]),
    "false",
    "id가 같아도 login이 다르면 거부한다",
  );
  assert.equal(
    reviewGate([[claudeReview(1, { user: { login: "claude-bot[bot]", id: 55, type: "Bot" } })]]),
    "false",
    "유사한 봇 login은 거부한다",
  );
  assert.equal(
    reviewGate([[claudeReview(1, { association: "CONTRIBUTOR" })]]),
    "false",
    "CodeRabbit과 같이 author_association NONE까지 고정한다",
  );
  assert.equal(
    reviewGate([[review(1, { state: "COMMENTED", user: { login: "claude", id: 77, type: "User" }, association: "COLLABORATOR" })]]),
    "false",
    "신뢰된 사람이 claude를 흉내 낸 마커 없는 COMMENTED는 discovery가 아니다",
  );
});

test("claude[bot]은 COMMENTED Review로만 discovery가 되고 자기 CHANGES_REQUESTED는 차단한다", () => {
  assert.equal(reviewGate([[claudeReview(1, { state: "APPROVED" })]]), "false", "봇 APPROVED는 discovery가 아니다");
  assert.equal(
    reviewGate([[claudeReview(1), claudeReview(2, { state: "CHANGES_REQUESTED" })]]),
    "false",
    "claude[bot]의 active change request는 차단한다",
  );
});

test("claude[bot] discovery 뒤 신뢰된 사람의 CHANGES_REQUESTED는 병합을 막는다", () => {
  assert.equal(
    reviewGate([[claudeReview(1), memberReview(2, "CHANGES_REQUESTED")]]),
    "false",
    "다른 reviewer의 active change request가 있으면 거부한다",
  );
  assert.equal(
    reviewGate([[claudeReview(1), ownerReview(2, "CHANGES_REQUESTED"), ownerReview(3, "COMMENTED")]]),
    "false",
    "후속 빈 COMMENTED가 change request를 지우지 않는다",
  );
  assert.equal(
    reviewGate([[claudeReview(1), memberReview(2, "CHANGES_REQUESTED"), memberReview(3, "APPROVED")]]),
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
