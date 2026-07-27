import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const contractUrl = new URL("../design/easysubway-color-system.json", import.meta.url);
const expectedTopLevel = ["version", "primitives", "semantic", "roleRestrictions", "contrastPairs"].sort();
const expectedPrimitiveKeys = [
  "brand.50", "brand.100", "brand.200", "brand.300", "brand.400", "brand.500",
  "brand.600", "brand.700", "brand.800", "brand.900", "brand.950",
  "neutral.white", "neutral.scaffold", "neutral.subtle", "neutral.border",
  "ink.secondary", "ink.muted", "status.success", "status.warning", "status.danger",
  "status.info", "status.successSoft", "status.warningSoft", "status.dangerSoft", "status.infoSoft",
].sort();
const expectedSemanticKeys = [
  "surface.default", "surface.scaffold", "surface.subtle", "surface.brandChrome",
  "surface.brand", "surface.brandStrong", "surface.signature", "border.subtle",
  "content.primary", "content.secondary", "content.muted", "interaction.primary",
  "interaction.primaryPressed", "interaction.onPrimary", "interaction.secondarySurface",
  "interaction.secondaryBorder", "interaction.secondaryPressedSurface",
  "interaction.secondaryPressedBorder", "interaction.onSignatureBorder", "interaction.onBrand",
  "focus.default", "focus.onSignature", "decorative.divider", "status.successContent",
  "status.successSurface", "status.warningContent", "status.warningSurface",
  "status.dangerContent", "status.dangerSurface", "status.infoContent", "status.infoSurface",
].sort();
const expectedRoleRestrictions = {
  "brand.300": {
    allow: ["decorative.divider"],
    deny: ["control.requiredBoundary", "focus.ring", "selection.soleVisualIndicator"],
  },
  "brand.400": {
    allow: ["surface.signature", "indicator.background"],
    deny: ["focus.ring", "selection.soleVisualIndicator", "control.requiredBoundary"],
  },
  "brand.500": {
    allow: ["brand.graphic"],
    deny: ["control.requiredBoundary", "status.soleIcon"],
  },
  "brand.600": {
    allow: ["interaction.secondaryBorder"],
    deny: ["surface.brandStrong.requiredBoundary", "surface.signature.requiredBoundary"],
  },
  "content.muted": {
    allow: ["surface.default", "surface.scaffold", "surface.brandChrome"],
    deny: ["surface.brand", "surface.brandStrong", "surface.signature"],
  },
};
const expectedPairIds = [
  "active-label-on-signature", "danger-content-on-danger-surface", "destructive-on-default",
  "focus-on-brand", "focus-on-brand-chrome", "focus-on-brand-strong", "focus-on-default",
  "focus-on-signature", "info-content-on-info-surface", "primary-action-content",
  "primary-action-pressed-content", "secondary-border", "secondary-content",
  "secondary-on-signature-border", "secondary-pressed-border", "secondary-pressed-content",
  "success-content-on-success-surface", "warning-content-on-warning-surface",
].sort();

async function readContract() {
  return JSON.parse(await readFile(contractUrl, "utf8"));
}

function relativeLuminance(hex) {
  const channels = hex.slice(1).match(/../g).map((value) => Number.parseInt(value, 16) / 255)
    .map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrastRatio(foreground, background) {
  const values = [relativeLuminance(foreground), relativeLuminance(background)].sort((a, b) => b - a);
  return (values[0] + 0.05) / (values[1] + 0.05);
}

test("색상 계약은 flat key와 닫힌 스키마를 가진다", async () => {
  const contract = await readContract();
  assert.deepEqual(Object.keys(contract).sort(), expectedTopLevel);
  assert.equal(contract.version, 1);
  assert.deepEqual(Object.keys(contract.primitives).sort(), expectedPrimitiveKeys);
  assert.deepEqual(Object.keys(contract.semantic).sort(), expectedSemanticKeys);
  assert.equal(contract.primitives["brand.50"], "#F8F9FF");
  assert.equal(contract.primitives["brand.400"], "#B4BCFB");
  for (const value of Object.values(contract.primitives)) assert.match(value, /^#[0-9A-F]{6}$/);
  assert.doesNotMatch(JSON.stringify(contract), /#F6F7FF|#FAFAFF/);
  for (const key of Object.keys(contract.semantic)) assert.ok(!(key in contract.primitives), `${key}: key 중복`);
});

test("Semantic과 역할 제한 참조는 닫혀 있다", async () => {
  const contract = await readContract();
  for (const [key, reference] of Object.entries(contract.semantic)) {
    assert.ok(reference in contract.primitives, `${key}: 알 수 없는 Primitive ${reference}`);
    if (/^status\..*Content$/.test(key)) assert.match(reference, /^status\./);
  }
  assert.deepEqual(contract.roleRestrictions, expectedRoleRestrictions);
  for (const key of Object.keys(contract.roleRestrictions)) {
    assert.ok(key in contract.primitives || key in contract.semantic, `${key}: 알 수 없는 제한 대상`);
  }
  const used = new Set(Object.values(contract.semantic));
  for (const key of Object.keys(contract.roleRestrictions)) if (key in contract.primitives) used.add(key);
  for (const key of Object.keys(contract.primitives)) assert.ok(used.has(key), `${key}: 미사용 Primitive`);
});

test("18개 Semantic Pair는 종류별 대비 하한을 충족한다", async () => {
  const contract = await readContract();
  const ids = contract.contrastPairs.map(({ id }) => id);
  assert.equal(new Set(ids).size, ids.length, "중복 Pair ID");
  assert.deepEqual([...ids].sort(), expectedPairIds);
  for (const pair of contract.contrastPairs) {
    assert.deepEqual(Object.keys(pair).sort(), ["id", "foregroundSemantic", "backgroundSemantic", "minimum", "kind"].sort());
    assert.ok(pair.foregroundSemantic in contract.semantic, `${pair.id}: 알 수 없는 전경 Semantic`);
    assert.ok(pair.backgroundSemantic in contract.semantic, `${pair.id}: 알 수 없는 배경 Semantic`);
    assert.ok(["text", "nonText"].includes(pair.kind), `${pair.id}: 알 수 없는 kind`);
    assert.equal(pair.minimum, pair.kind === "text" ? 4.5 : 3);
    const foreground = contract.primitives[contract.semantic[pair.foregroundSemantic]];
    const background = contract.primitives[contract.semantic[pair.backgroundSemantic]];
    const ratio = contrastRatio(foreground, background);
    assert.ok(ratio >= pair.minimum, `${pair.id}: ${ratio.toFixed(4)}:1 < ${pair.minimum}:1`);
  }
});
