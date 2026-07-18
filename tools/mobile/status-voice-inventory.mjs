#!/usr/bin/env node
// 상태 요약 라벨 voice 인벤토리 producer (#1778 단일 소유).
//
// apps/mobile/lib 의 사용자 노출 상태 요약 문자열을 현재 tree에서 재생성하고,
// 각 항목을 상태 분류(stateClass)·소유 이슈(owner)·처리(disposition)로 분류한
// machine-readable JSON report를 만든다. 같은 tree에서 재실행하면 동일한 결과를
// 낸다(결정적). 다른 카피 이슈는 이 report를 소비한다.
//
// 사용법:
//   node tools/mobile/status-voice-inventory.mjs            # JSON을 stdout으로
//   node tools/mobile/status-voice-inventory.mjs --pretty   # 들여쓴 JSON
//   node tools/mobile/status-voice-inventory.mjs --summary  # disposition 분포만
//   node tools/mobile/status-voice-inventory.mjs --root <dir>
//
// stateClass:
//   loading          실제 로딩/진행 중 — 진행형이 올바른 voice
//   no-data          데이터가 비어 있음(빈 목록·빈 값·조회 실패 fallback)
//   unsupported      기능/데이터 미지원
//   stale-unknown    상태가 미확인·오래됨(진행 중 아님)
//   static-label     정해진 사실(불리언 플래그·확정 분류)
//   uncertainty-hedge 헤지 사전(#1577)이 소유한 불확실성 문구 — 진행형 유지
//   coming-soon      '준비 중' 계열
//   diagnostic       운영/진단 로그(context:) — 사용자 비노출
//   unclassified     신호는 잡혔으나 규칙 미매칭 — drift 감시용
//
// disposition:
//   keep            현재 voice 유지(실제 로딩·헤지 등)
//   reword          사실형 문구로 정렬 대상(#1778)
//   aligned         이미 사실형으로 정렬됨
//   reuse-catalog   헤지 사전 공용 문구 재사용 대상(#1778)
//   out-of-scope    타 이슈 소유 또는 비노출
//   review          규칙 미매칭 — 사람이 판단 필요

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = fileURLToPath(new URL('.', import.meta.url));
const DEFAULT_ROOT = join(HERE, '..', '..');

// 상태 요약 voice 신호. 이 중 하나라도 포함한 리터럴만 인벤토리 후보다.
const SIGNAL = /확인하고 있어요|확인 중|불러오는 중|조회 중|준비\s?중|미확인/;

// route_search.dart 등 일부 소스에 섞인 NUL 바이트 제거용. 정규식 리터럴에
// 제어문자 코드포인트를 직접 담지 않도록 String.fromCharCode로 만든다.
const NUL_CHARACTER = String.fromCharCode(0);

// 실측을 거쳐 실제 loading으로 확인된 문구만 여기 명시적으로 나열한다. 새
// '확인 중'류 문자열이 발견되면 이 목록에 없는 한 review로 떨어져야 한다
// (CodeRabbit finding: 포괄 정규식은 drift 감시 계약을 깨뜨린다).
const VERIFIED_LOADING_TEXTS = new Set([
  '확인 중',
  '제보 진행 상황 확인 중',
  '즐겨찾기 확인 중',
  '현재 위치 확인 중',
  '실시간 정보 확인 중',
  '알림 확인 중',
  '신뢰도 확인 중',
]);

// 규칙 카탈로그. 위에서부터 첫 매칭이 이긴다. 각 규칙은 리터럴 text(정규식)·
// 정확히 일치하는 문자열 집합(oneOf)과 선택적으로 파일 경로 조건(fileRe)·
// 원본 라인 포함 조건(lineHas)을 본다.
const RULES = [
  // 운영/진단 로그: context: 인자로 넘어가는 문자열은 사용자 비노출.
  {
    lineHas: 'context:',
    stateClass: 'diagnostic',
    owner: 'none',
    disposition: 'out-of-scope',
    note: '예외 로그 context — 사용자 비노출',
  },

  // '준비 중' 계열은 #2078가 소유(빈 상태 layout·ghost node 정리와 함께).
  {
    text: /준비\s?중/,
    stateClass: 'coming-soon',
    owner: '#2078',
    disposition: 'out-of-scope',
    note: '준비 중 문구 — #2078 소유',
  },

  // 헤지 사전(#1577) 소유 불확실성 문구. 진행형 유지, 공용 catalog가 소유.
  {
    text: /^(계단 없는 길인지|엘리베이터·통로 상태를|길이 이어지는지|일부 안내를) 확인하고 있어요\.$/,
    stateClass: 'uncertainty-hedge',
    owner: '#1778',
    disposition: 'keep',
    note: 'route_hedge_labels 공용 헤지 — #1577 확정',
  },
  {
    text: /^소요 시간을 확인하고 있어요\.$/,
    fileRe: /route_engine\.dart$/,
    stateClass: 'uncertainty-hedge',
    owner: '#1778',
    disposition: 'reuse-catalog',
    note: 'catalog DURATION_UNKNOWN와 중복 리터럴 — 공용 문구 재사용',
  },
  {
    text: /^소요 시간을 확인하고 있어요\.$/,
    stateClass: 'uncertainty-hedge',
    owner: '#1778',
    disposition: 'keep',
    note: 'catalog DURATION_UNKNOWN 헤지',
  },

  // 실제 로딩/진행 중: 진행형이 올바른 voice.
  {
    text: /불러오는 중/,
    stateClass: 'loading',
    owner: '#1778',
    disposition: 'keep',
    note: '실제 데이터 로딩 라벨',
  },
  {
    text: /^도착 시간을 확인하고 있어요\.$/,
    stateClass: 'loading',
    owner: '#1778',
    disposition: 'keep',
    note: '실시간 새로고침 진행 중',
  },
  {
    text: /^계단 여부를 확인하고 있어요$/,
    stateClass: 'uncertainty-hedge',
    owner: '#1778',
    disposition: 'keep',
    note: '계단 상태 불확실성 — 헤지 voice 유지',
  },
  {
    text: /^경로 상태를 확인하고 있어요$/,
    stateClass: 'uncertainty-hedge',
    owner: '#1778',
    disposition: 'keep',
    note: '경로 상태 불확실성(REVIEW/UNKNOWN) — 헤지 voice 유지',
  },
  {
    text: /^도착 정보를 확인하고 있어요$/,
    stateClass: 'loading',
    owner: '#1778',
    disposition: 'keep',
    note: '도착 정보 출처 미도착 — 진행 중',
  },

  // #1778 정렬 대상: 진행형이 사실(플래그/빈 데이터/미확인)을 진행 중으로 오인시킴.
  {
    text: /^에스컬레이터 안내를 확인하고 있어요$/,
    stateClass: 'static-label',
    owner: '#1778',
    disposition: 'reword',
    note: 'requiresEscalator=참(사실) → 사실형',
  },
  {
    text: /^상태를 확인하고 있어요$/,
    stateClass: 'stale-unknown',
    owner: '#1778',
    disposition: 'reword',
    note: '시설 상태 미확인 → 사실형',
  },
  {
    text: /^확인 중$/,
    fileRe: /facility_status\.dart$/,
    stateClass: 'stale-unknown',
    owner: '#1778',
    disposition: 'reword',
    note: '시설 상태 severity 미확인 → 사실형',
  },
  {
    text: /^노선을 확인하고 있어요$/,
    stateClass: 'no-data',
    owner: '#1778',
    disposition: 'reword',
    note: '노선 목록 비어 있음(no-data) → 사실형',
  },
  {
    text: /^엘리베이터 연결을 확인하고 있어요$/,
    stateClass: 'stale-unknown',
    owner: '#1778',
    disposition: 'reword',
    note: '엘리베이터 연결 미확인 → 사실형',
  },
  {
    text: /^연결 위치를 확인하고 있어요$/,
    stateClass: 'no-data',
    owner: '#1778',
    disposition: 'reword',
    note: '연결 위치 정보 비어 있음 → 사실형',
  },
  {
    text: /^역 이름을 확인하고 있어요$/,
    stateClass: 'no-data',
    owner: '#1778',
    disposition: 'reword',
    note: '역 이름 조회 실패 fallback → 사실형',
  },
  {
    text: /^일부 도착정보를 확인하고 있어요$/,
    stateClass: 'static-label',
    owner: '#1778',
    disposition: 'reword',
    note: 'ETA 출처 MIXED(사실) → 사실형',
  },
  {
    text: /^이동 부담을 확인하고 있어요$/,
    stateClass: 'no-data',
    owner: '#1778',
    disposition: 'reword',
    note: '차단/무경로로 이동 부담 없음 → 사실형',
  },
  {
    text: /^시간 또는 거리를 확인하고 있어요$/,
    stateClass: 'stale-unknown',
    owner: '#1778',
    disposition: 'reword',
    note: '시간·거리 출처 UNKNOWN → 사실형',
  },
  {
    text: /^시간을 확인하고 있어요$/,
    stateClass: 'no-data',
    owner: '#1778',
    disposition: 'reword',
    note: '소요 시간 값 없음 → 사실형',
  },
  {
    text: /^거리를 확인하고 있어요$/,
    stateClass: 'no-data',
    owner: '#1778',
    disposition: 'reword',
    note: '거리 값 없음 → 사실형',
  },

  // 이미 사실형으로 정렬된 문구('미확인' 어휘)는 aligned로 남긴다.
  {
    text: /미확인/,
    stateClass: 'stale-unknown',
    owner: '#1778',
    disposition: 'aligned',
    note: '사실형 미확인 voice',
  },

  // 검증된 실제 loading 문구만 명시적으로 열거한다(포괄 '확인 중' 정규식 금지).
  // 이 allowlist에 없는 새 진행형/'확인 중' 계열 문자열은 아래 fallback을 타
  // review로 떨어지므로, drift는 사람이 판단하기 전까지 자동 loading으로
  // 확정되지 않는다.
  {
    oneOf: VERIFIED_LOADING_TEXTS,
    stateClass: 'loading',
    owner: '#1778',
    disposition: 'keep',
    note: '검증된 진행 중 상태 라벨(allowlist)',
  },
];

function listDartFiles(dir, acc) {
  for (const entry of readdirSync(dir).sort()) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      listDartFiles(full, acc);
    } else if (entry.endsWith('.dart')) {
      acc.push(full);
    }
  }
  return acc;
}

// 한 줄에서 홑따옴표 문자열 리터럴을 추출한다. 이스케이프된 홑따옴표(\')는
// 문자열 내부로 보고 이어 붙인다. 상태 라벨은 단순 리터럴이라 이 정도로 충분하다.
function extractSingleQuoted(line) {
  const out = [];
  let i = 0;
  while (i < line.length) {
    if (line[i] !== "'") {
      i += 1;
      continue;
    }
    let j = i + 1;
    let buf = '';
    let closed = false;
    while (j < line.length) {
      const ch = line[j];
      if (ch === '\\' && j + 1 < line.length) {
        buf += line[j + 1];
        j += 2;
        continue;
      }
      if (ch === "'") {
        closed = true;
        break;
      }
      buf += ch;
      j += 1;
    }
    if (!closed) {
      break;
    }
    out.push(buf);
    i = j + 1;
  }
  return out;
}

// entries 정렬 비교자. 중첩 삼항 대신 독립 조건문으로 file → line → text
// 우선순위를 판정한다.
function compareEntries(a, b) {
  if (a.file !== b.file) {
    return a.file.localeCompare(b.file);
  }
  if (a.line !== b.line) {
    return a.line - b.line;
  }
  return a.text.localeCompare(b.text);
}

function classify(text, relFile, rawLine) {
  for (const rule of RULES) {
    if (rule.lineHas && !rawLine.includes(rule.lineHas)) {
      continue;
    }
    if (rule.text && !rule.text.test(text)) {
      continue;
    }
    if (rule.oneOf && !rule.oneOf.has(text)) {
      continue;
    }
    if (rule.fileRe && !rule.fileRe.test(relFile)) {
      continue;
    }
    return {
      stateClass: rule.stateClass,
      owner: rule.owner,
      disposition: rule.disposition,
      note: rule.note,
    };
  }
  return {
    stateClass: 'unclassified',
    owner: 'none',
    disposition: 'review',
    note: '상태 신호 감지, 규칙 미매칭 — 사람 판단 필요',
  };
}

export function buildInventory(root = DEFAULT_ROOT) {
  const libDir = join(root, 'apps', 'mobile', 'lib');
  const files = listDartFiles(libDir, []);
  const entries = [];
  for (const file of files) {
    // NUL 바이트가 섞인 소스도 있어(route_search.dart) 제거 후 읽는다. 정규식에
    // 제어문자를 담지 않도록 String.fromCharCode로 문자를 만들어 전역 치환한다.
    const content = readFileSync(file, 'utf8').replaceAll(NUL_CHARACTER, '');
    const relFile = relative(root, file).split(sep).join('/');
    const lines = content.split('\n');
    for (let idx = 0; idx < lines.length; idx += 1) {
      const rawLine = lines[idx];
      for (const text of extractSingleQuoted(rawLine)) {
        if (!SIGNAL.test(text)) {
          continue;
        }
        const verdict = classify(text, relFile, rawLine);
        entries.push({ file: relFile, line: idx + 1, text, ...verdict });
      }
    }
  }
  entries.sort(compareEntries);
  const byDisposition = {};
  const byStateClass = {};
  const byOwner = {};
  for (const e of entries) {
    byDisposition[e.disposition] = (byDisposition[e.disposition] ?? 0) + 1;
    byStateClass[e.stateClass] = (byStateClass[e.stateClass] ?? 0) + 1;
    byOwner[e.owner] = (byOwner[e.owner] ?? 0) + 1;
  }
  return {
    schema: 'easysubway/mobile-status-voice-inventory@1',
    producer: 'tools/mobile/status-voice-inventory.mjs',
    ownerIssue: '#1778',
    total: entries.length,
    byDisposition,
    byStateClass,
    byOwner,
    entries,
  };
}

function main() {
  const argv = process.argv.slice(2);
  let root = DEFAULT_ROOT;
  const rootIdx = argv.indexOf('--root');
  if (rootIdx !== -1) {
    root = argv[rootIdx + 1];
  }
  const report = buildInventory(root);
  if (argv.includes('--summary')) {
    process.stdout.write(
      JSON.stringify(
        {
          total: report.total,
          byDisposition: report.byDisposition,
          byStateClass: report.byStateClass,
          byOwner: report.byOwner,
        },
        null,
        2,
      ) + '\n',
    );
    return;
  }
  const pretty = argv.includes('--pretty');
  process.stdout.write(
    JSON.stringify(report, null, pretty ? 2 : 0) + '\n',
  );
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main();
}
