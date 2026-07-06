import assert from "node:assert/strict";
import test from "node:test";
import {
  MAIN_RULESET_ID,
  REQUIRED_STATUS_CHECK_CONTEXTS,
  ensureRequiredChecks,
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
  assert.deepEqual(added, ["Release Gate Consistency", "PR Title"]);
  const rule = ruleset.rules.find((entry) => entry.type === "required_status_checks");
  const contexts = rule.parameters.required_status_checks.map((check) => check.context);
  assert.deepEqual(contexts, REQUIRED_STATUS_CHECK_CONTEXTS);
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

test("targets the documented main ruleset id and the seven gate contexts", () => {
  assert.equal(MAIN_RULESET_ID, "17584352");
  assert.deepEqual(REQUIRED_STATUS_CHECK_CONTEXTS, [
    "Changes",
    "Repository CI",
    "Backend CI",
    "Mobile App CI",
    "Android CI",
    "Release Gate Consistency",
    "PR Title",
  ]);
});
