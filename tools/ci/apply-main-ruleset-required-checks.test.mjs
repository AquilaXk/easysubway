import assert from "node:assert/strict";
import test from "node:test";
import {
  MAIN_RULESET_ID,
  REQUIRED_STATUS_CHECK_CONTEXTS,
  ensureRequiredChecks,
  toWritableRuleset,
} from "./apply-main-ruleset-required-checks.mjs";

function baselineRuleset() {
  return {
    id: 17584352,
    name: "main",
    target: "branch",
    enforcement: "active",
    conditions: { ref_name: { include: ["~DEFAULT_BRANCH"], exclude: [] } },
    rules: [
      { type: "deletion" },
      {
        type: "required_status_checks",
        parameters: {
          strict_required_status_checks_policy: true,
          required_status_checks: [
            { context: "Changes" },
            { context: "Repository CI" },
            { context: "Backend CI" },
            { context: "Mobile App CI" },
            { context: "Android CI" },
          ],
        },
      },
    ],
  };
}

test("adds only the missing contexts and reports them", () => {
  const { ruleset, added } = ensureRequiredChecks(baselineRuleset(), REQUIRED_STATUS_CHECK_CONTEXTS);
  assert.deepEqual(added, ["Admin QA Gates", "Release Gate Consistency", "PR Title"]);
  const rule = ruleset.rules.find((entry) => entry.type === "required_status_checks");
  const contexts = rule.parameters.required_status_checks.map((check) => check.context);
  assert.deepEqual(contexts, [
    "Changes",
    "Repository CI",
    "Backend CI",
    "Mobile App CI",
    "Android CI",
    "Admin QA Gates",
    "Release Gate Consistency",
    "PR Title",
  ]);
  assert.deepEqual(new Set(contexts), new Set(REQUIRED_STATUS_CHECK_CONTEXTS));
  // Strict policy and other rules are preserved.
  assert.equal(rule.parameters.strict_required_status_checks_policy, true);
  assert.ok(ruleset.rules.some((entry) => entry.type === "deletion"));
});

test("is idempotent once all contexts are present", () => {
  const once = ensureRequiredChecks(baselineRuleset(), REQUIRED_STATUS_CHECK_CONTEXTS).ruleset;
  const { added } = ensureRequiredChecks(once, REQUIRED_STATUS_CHECK_CONTEXTS);
  assert.deepEqual(added, []);
});

test("does not mutate the input ruleset", () => {
  const input = baselineRuleset();
  ensureRequiredChecks(input, REQUIRED_STATUS_CHECK_CONTEXTS);
  const rule = input.rules.find((entry) => entry.type === "required_status_checks");
  assert.equal(rule.parameters.required_status_checks.length, 5);
});

test("throws when the ruleset has no required_status_checks rule", () => {
  const ruleset = { rules: [{ type: "deletion" }] };
  assert.throws(() => ensureRequiredChecks(ruleset, REQUIRED_STATUS_CHECK_CONTEXTS), /no required_status_checks rule/);
});

test("toWritableRuleset keeps only the PUT-writable fields and drops read-only envelope", () => {
  const fromGet = {
    id: 17584352,
    node_id: "RRS_x",
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-02T00:00:00Z",
    source_type: "Repository",
    source: "AquilaXk/easysubway",
    current_user_can_bypass: "always",
    _links: { self: { href: "..." } },
    name: "main",
    target: "branch",
    enforcement: "active",
    bypass_actors: [{ actor_id: 1 }],
    conditions: { ref_name: { include: ["~DEFAULT_BRANCH"], exclude: [] } },
    rules: [{ type: "deletion" }],
  };
  const writable = toWritableRuleset(fromGet);
  assert.deepEqual(
    Object.keys(writable).sort(),
    ["bypass_actors", "conditions", "enforcement", "name", "rules", "target"],
  );
  for (const readOnly of ["id", "node_id", "created_at", "updated_at", "source", "_links", "current_user_can_bypass"]) {
    assert.ok(!(readOnly in writable), `${readOnly} must be dropped`);
  }
  assert.equal(writable.name, "main");
  assert.deepEqual(writable.rules, [{ type: "deletion" }]);
});

test("targets the documented main ruleset id and the eight gate contexts", () => {
  assert.equal(MAIN_RULESET_ID, "17584352");
  assert.deepEqual(REQUIRED_STATUS_CHECK_CONTEXTS, [
    "Changes",
    "Repository CI",
    "Admin QA Gates",
    "Backend CI",
    "Mobile App CI",
    "Android CI",
    "Release Gate Consistency",
    "PR Title",
  ]);
});
