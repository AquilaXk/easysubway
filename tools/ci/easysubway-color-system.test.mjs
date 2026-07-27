import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const contractUrl = new URL("../design/easysubway-color-system.json", import.meta.url);
const expectedTopLevel = ["version", "primitives", "semantic", "roleRestrictions", "contrastPairs"].sort();
const expectedPrimitives = {
  "brand.50": "#F8F9FF",
  "brand.100": "#F0F2FE",
  "brand.200": "#E2E5FD",
  "brand.300": "#CCD2FC",
  "brand.400": "#B4BCFB",
  "brand.500": "#949FE8",
  "brand.600": "#7480D2",
  "brand.700": "#5C6BC0",
  "brand.800": "#4A58A9",
  "brand.900": "#3B4890",
  "brand.950": "#1F2340",
  "neutral.white": "#FFFFFF",
  "neutral.scaffold": "#F7F8FC",
  "neutral.subtle": "#F0F2F7",
  "neutral.border": "#E1E4EE",
  "ink.secondary": "#4D536B",
  "ink.muted": "#697089",
  "status.success": "#0A705A",
  "status.warning": "#9A5600",
  "status.danger": "#B42318",
  "status.info": "#215EA8",
  "status.successSoft": "#F0FBF7",
  "status.warningSoft": "#FFF0D1",
  "status.dangerSoft": "#FFE8E6",
  "status.infoSoft": "#EEF5FF",
};
const expectedSemantic = {
  "surface.default": "neutral.white",
  "surface.scaffold": "neutral.scaffold",
  "surface.subtle": "neutral.subtle",
  "surface.brandChrome": "brand.50",
  "surface.brand": "brand.100",
  "surface.brandStrong": "brand.200",
  "surface.signature": "brand.400",
  "border.subtle": "neutral.border",
  "content.primary": "brand.950",
  "content.secondary": "ink.secondary",
  "content.muted": "ink.muted",
  "interaction.primary": "brand.700",
  "interaction.primaryPressed": "brand.800",
  "interaction.onPrimary": "neutral.white",
  "interaction.secondarySurface": "brand.100",
  "interaction.secondaryBorder": "brand.600",
  "interaction.secondaryPressedSurface": "brand.200",
  "interaction.secondaryPressedBorder": "brand.700",
  "interaction.onSignatureBorder": "brand.900",
  "interaction.onBrand": "brand.900",
  "focus.default": "brand.700",
  "focus.onSignature": "brand.900",
  "decorative.divider": "brand.300",
  "status.successContent": "status.success",
  "status.successSurface": "status.successSoft",
  "status.warningContent": "status.warning",
  "status.warningSurface": "status.warningSoft",
  "status.dangerContent": "status.danger",
  "status.dangerSurface": "status.dangerSoft",
  "status.infoContent": "status.info",
  "status.infoSurface": "status.infoSoft",
};
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
const expectedPairs = {
  "primary-action-content": ["interaction.onPrimary", "interaction.primary", 4.5, "text"],
  "primary-action-pressed-content": ["interaction.onPrimary", "interaction.primaryPressed", 4.5, "text"],
  "secondary-content": ["interaction.onBrand", "interaction.secondarySurface", 4.5, "text"],
  "secondary-pressed-content": ["interaction.onBrand", "interaction.secondaryPressedSurface", 4.5, "text"],
  "secondary-border": ["interaction.secondaryBorder", "interaction.secondarySurface", 3, "nonText"],
  "secondary-pressed-border": ["interaction.secondaryPressedBorder", "interaction.secondaryPressedSurface", 3, "nonText"],
  "secondary-on-signature-border": ["interaction.onSignatureBorder", "surface.signature", 3, "nonText"],
  "focus-on-default": ["focus.default", "surface.default", 3, "nonText"],
  "focus-on-brand-chrome": ["focus.default", "surface.brandChrome", 3, "nonText"],
  "focus-on-brand": ["focus.default", "surface.brand", 3, "nonText"],
  "focus-on-brand-strong": ["focus.default", "surface.brandStrong", 3, "nonText"],
  "focus-on-signature": ["focus.onSignature", "surface.signature", 3, "nonText"],
  "active-label-on-signature": ["interaction.onBrand", "surface.signature", 4.5, "text"],
  "destructive-on-default": ["status.dangerContent", "surface.default", 4.5, "text"],
  "success-content-on-success-surface": ["status.successContent", "status.successSurface", 4.5, "text"],
  "warning-content-on-warning-surface": ["status.warningContent", "status.warningSurface", 4.5, "text"],
  "danger-content-on-danger-surface": ["status.dangerContent", "status.dangerSurface", 4.5, "text"],
  "info-content-on-info-surface": ["status.infoContent", "status.infoSurface", 4.5, "text"],
};

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
  assert.deepEqual(contract.primitives, expectedPrimitives);
  assert.deepEqual(contract.semantic, expectedSemantic);
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
  assert.deepEqual(
    Object.fromEntries(contract.contrastPairs.map((pair) => [
      pair.id,
      [pair.foregroundSemantic, pair.backgroundSemantic, pair.minimum, pair.kind],
    ])),
    expectedPairs,
  );
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
