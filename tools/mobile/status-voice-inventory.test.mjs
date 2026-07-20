import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

import { buildInventory } from './status-voice-inventory.mjs';

const REPO_ROOT = join(fileURLToPath(new URL('.', import.meta.url)), '..', '..');

function withFixture(dartByFile, run) {
  const root = mkdtempSync(join(tmpdir(), 'status-voice-'));
  try {
    const libDir = join(root, 'apps', 'mobile', 'lib');
    for (const [rel, content] of Object.entries(dartByFile)) {
      const full = join(libDir, rel);
      mkdirSync(join(full, '..'), { recursive: true });
      writeFileSync(full, content, 'utf8');
    }
    return run(buildInventory(root));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function entryFor(report, text) {
  return report.entries.find((e) => e.text === text);
}

test('진행형 시설 상태는 reword/stale-unknown으로 분류한다', () => {
  withFixture(
    { 'facility_status.dart': "const x = '상태를 확인하고 있어요';\n" },
    (report) => {
      const e = entryFor(report, '상태를 확인하고 있어요');
      assert.equal(e.disposition, 'reword');
      assert.equal(e.stateClass, 'stale-unknown');
      assert.equal(e.owner, '#1778');
    },
  );
});

test('facility_status의 확인 중 severity는 reword, 그 외 확인 중은 keep', () => {
  withFixture(
    {
      'facility_status.dart': "const s = '확인 중';\n",
      'notification_settings.dart': "final t = isBusy ? '확인 중' : 'x';\n",
    },
    (report) => {
      const facility = report.entries.find(
        (e) => e.file.endsWith('facility_status.dart') && e.text === '확인 중',
      );
      const other = report.entries.find(
        (e) =>
          e.file.endsWith('notification_settings.dart') && e.text === '확인 중',
      );
      assert.equal(facility.disposition, 'reword');
      assert.equal(other.disposition, 'keep');
      assert.equal(other.stateClass, 'loading');
    },
  );
});

test('allowlist에 있는 검증된 loading 문구는 여전히 keep/loading이다', () => {
  const verifiedTexts = [
    '확인 중',
    '제보 진행 상황 확인 중',
    '즐겨찾기 확인 중',
    '현재 위치 확인 중',
    '실시간 정보 확인 중',
    '알림 확인 중',
    '신뢰도 확인 중',
  ];
  const files = Object.fromEntries(
    verifiedTexts.map((text, i) => [
      `allowlist_${i}.dart`,
      `const x = '${text}';\n`,
    ]),
  );
  withFixture(files, (report) => {
    for (const text of verifiedTexts) {
      const e = entryFor(report, text);
      assert.equal(e.stateClass, 'loading', `${text} stateClass`);
      assert.equal(e.disposition, 'keep', `${text} disposition`);
    }
  });
});

test('allowlist에 없는 새 진행형/확인 중 문구는 review로 떨어진다(drift 회귀)', () => {
  withFixture(
    { 'new_screen.dart': "const label = '새 기능 확인 중';\n" },
    (report) => {
      const e = entryFor(report, '새 기능 확인 중');
      assert.equal(e.stateClass, 'unclassified');
      assert.equal(e.disposition, 'review');
    },
  );
});

test('allowlist에 없는 새 확인하고 있어요 계열도 review로 떨어진다(drift 회귀)', () => {
  withFixture(
    { 'new_screen.dart': "const label = '새 항목을 확인하고 있어요';\n" },
    (report) => {
      const e = entryFor(report, '새 항목을 확인하고 있어요');
      assert.equal(e.stateClass, 'unclassified');
      assert.equal(e.disposition, 'review');
    },
  );
});

test("'준비 중'은 #2078 out-of-scope로 소유권만 표시한다", () => {
  withFixture(
    { 'route_search.dart': "const p = '실시간 도착정보 준비 중';\n" },
    (report) => {
      const e = entryFor(report, '실시간 도착정보 준비 중');
      assert.equal(e.owner, '#2078');
      assert.equal(e.disposition, 'out-of-scope');
      assert.equal(e.stateClass, 'coming-soon');
    },
  );
});

test('context: 진단 로그는 사용자 비노출 out-of-scope로 분류한다', () => {
  withFixture(
    {
      'network_map.dart':
        "reporter.log(context: 'manifest를 불러오는 중 예외가 발생했습니다.');\n",
    },
    (report) => {
      const e = report.entries.find((x) => x.text.includes('불러오는 중'));
      assert.equal(e.stateClass, 'diagnostic');
      assert.equal(e.disposition, 'out-of-scope');
      assert.equal(e.owner, 'none');
    },
  );
});

test("사용자 노출 '불러오는 중' 라벨은 loading keep", () => {
  withFixture(
    { 'app.dart': "const label = '쉬운 지하철을 불러오는 중';\n" },
    (report) => {
      const e = entryFor(report, '쉬운 지하철을 불러오는 중');
      assert.equal(e.stateClass, 'loading');
      assert.equal(e.disposition, 'keep');
    },
  );
});

test('헤지 사전 공용 문구는 uncertainty-hedge keep', () => {
  withFixture(
    {
      'route_hedge_labels.dart':
        "const h = '엘리베이터·통로 상태를 확인하고 있어요.';\n",
    },
    (report) => {
      const e = entryFor(report, '엘리베이터·통로 상태를 확인하고 있어요.');
      assert.equal(e.stateClass, 'uncertainty-hedge');
      assert.equal(e.disposition, 'keep');
    },
  );
});

test('사실형 미확인 문구는 aligned로 분류한다', () => {
  withFixture(
    { 'facility_status.dart': "const a = '상태 미확인';\n" },
    (report) => {
      const e = entryFor(report, '상태 미확인');
      assert.equal(e.disposition, 'aligned');
      assert.equal(e.stateClass, 'stale-unknown');
    },
  );
});

test('같은 tree에서 재실행하면 결정적으로 동일한 report를 낸다', () => {
  const a = buildInventory(REPO_ROOT);
  const b = buildInventory(REPO_ROOT);
  assert.deepEqual(a, b);
});

test('현재 tree에는 분류 불가(unclassified/review) 항목이 없다', () => {
  const report = buildInventory(REPO_ROOT);
  const stray = report.entries.filter(
    (e) => e.stateClass === 'unclassified' || e.disposition === 'review',
  );
  assert.deepEqual(
    stray,
    [],
    `미분류 상태 문자열이 있습니다: ${JSON.stringify(stray)}`,
  );
  assert.ok(report.total > 0);
});
