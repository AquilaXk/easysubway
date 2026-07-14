# ITX-청춘 Completeness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** #2116을 세 service day의 전체 roster·양방향·전체 trip·계획 시각이 완전할 때만 admission하는 fail-closed 계약으로 갱신한다.

**Architecture:** 기존 TAGO/KORAIL parser와 pagination을 재사용한다. TAGO는 경춘선 roster 탐색 OD matrix를 만들고, KORAIL은 roster 열차의 경춘선 밖 여객 정차까지 `trn_run_sn` 순서로 materialize한다. 세 날짜 orchestration과 release wiring 검증만 기존 파일에 추가한다.

**Tech Stack:** Node.js ESM, `node:test`, stdlib `crypto`/`Intl`, better-sqlite3 기반 기존 pack reader

## Global Constraints

- 새 dependency와 fallback을 추가하지 않는다.
- live admission 날짜는 Asia/Seoul 실행일 기준 오늘~6일이며 `dayCd 8/7/9` 날짜를 모두 명시한다.
- replay는 `admissionStatus: REPLAY_ONLY`, `admissionEligible: false`다.
- consumer는 #1400, #2098, #2099만 허용하며 #2094 wiring은 0건이다.
- 한 날짜라도 roster·방향·시종착·정차·시각이 불완전하면 `MISSING` artifact를 쓰고 non-zero 종료한다.

---

### Task 1: 날짜와 OD matrix 계약

**Files:**
- Modify: `tools/datapack/collect-tago-itx-cheongchun-od.mjs`
- Modify: `tools/datapack/collect-tago-itx-cheongchun-od.test.mjs`

**Interfaces:**
- Produces: `validateItxServiceDates(serviceDates, { now, replay })`
- Produces: `buildItxOdMatrix(date, stations)` returning `{ rows, expectedOdCount, stationSetHash, odMatrixHash }`
- Produces: `collectTagoItxCheongchunRoster(options)`

- [x] **Step 1: Write failing date and canonical hash tests**

```js
assert.deepEqual(validateItxServiceDates(
  { "8": "20260715", "7": "20260718", "9": "20260719" },
  { now: new Date("2026-07-14T15:00:00.000Z"), replay: false },
), { "8": "20260715", "7": "20260718", "9": "20260719" });
assert.throws(() => validateItxServiceDates(
  { "8": "20260713", "7": "20260718", "9": "20260719" },
  { now: new Date("2026-07-14T00:00:00.000Z"), replay: false },
), /today through 6 days/);

const matrix = buildItxOdMatrix("20260715", [
  { providerStationId: "B" },
  { providerStationId: "A" },
]);
assert.deepEqual(matrix.rows, [
  { date: "20260715", depStationId: "A", arrStationId: "B" },
  { date: "20260715", depStationId: "B", arrStationId: "A" },
]);
assert.equal(matrix.expectedOdCount, 2);
assert.equal(matrix.odMatrixHash, sha256(JSON.stringify([
  ["20260715", "A", "B"],
  ["20260715", "B", "A"],
])));
```

`odMatrixHash`의 canonical serialization은 `(date, depStationId, arrStationId)`로 정렬한 tuple 배열의 공백 없는 `JSON.stringify` UTF-8 bytes다.

- [x] **Step 2: Run the focused tests and confirm RED**

Run: `node --test tools/datapack/collect-tago-itx-cheongchun-od.test.mjs`

Expected: FAIL because the three exports do not exist.

- [x] **Step 3: Implement the minimal stdlib validation and matrix builder**

```js
export function buildItxOdMatrix(date, stations) {
  const ids = stations.map(({ providerStationId }) => requiredString(providerStationId, "providerStationId")).sort();
  if (ids.length < 2 || new Set(ids).size !== ids.length) {
    throw new Error("ITX roster stations must be unique and contain at least 2 stations");
  }
  const rows = ids.flatMap((depStationId) => ids
    .filter((arrStationId) => arrStationId !== depStationId)
    .map((arrStationId) => ({ date, depStationId, arrStationId })));
  return {
    rows,
    expectedOdCount: ids.length * (ids.length - 1),
    stationSetHash: sha256(JSON.stringify(ids)),
    odMatrixHash: sha256(JSON.stringify(rows.map(({ date: d, depStationId, arrStationId }) => [d, depStationId, arrStationId]))),
  };
}
```

`validateItxServiceDates`는 KST 현재 날짜를 `Intl.DateTimeFormat`으로 구하고 UTC calendar arithmetic으로 inclusive 0~6일과 요일(8=월~금, 7=토, 9=일)을 검사한다. `replay`일 때만 freshness를 건너뛴다.

- [x] **Step 4: Extend the existing TAGO collector to full OD roster**

`collectTagoItxCheongchunRoster`는 기존 grade/city/station fetch를 한 번만 수행하고 canonical 경춘선 역 이름을 TAGO station ID로 유일 mapping한다. `buildItxOdMatrix`의 각 row를 기존 `fetchAll("GetStrtpntAlocFndTrainInfo", ...)`에 전달하고 전 페이지 결과를 합쳐 다음 값을 반환한다.

```js
{
  artifactKind: "tago-itx-cheongchun-roster-evidence",
  trainNumbers: [...new Set(itineraries.map((row) => row.trainNumber))].sort(naturalCompare),
  expectedOdCount,
  completedOdCount: rows.length,
  failedOdCount: 0,
  stationSetHash,
  odMatrixHash,
  itineraries,
  credentialRedacted: true,
}
```

- [x] **Step 5: Run GREEN and commit**

Run: `node --test tools/datapack/collect-tago-itx-cheongchun-od.test.mjs`

Expected: PASS.

```sh
git add tools/datapack/collect-tago-itx-cheongchun-od.mjs tools/datapack/collect-tago-itx-cheongchun-od.test.mjs
git commit -m "feat: collect complete ITX roster matrix"
```

### Task 2: 전체 KORAIL trip materialization과 완전성

**Files:**
- Modify: `tools/datapack/collect-korail-itx-cheongchun-timetable.mjs`
- Modify: `tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs`

**Interfaces:**
- Consumes: `tago-itx-cheongchun-roster-evidence`
- Produces: 날짜별 artifact의 `directions`, `terminalVariants`, `trainNumberSets`, `materialization`

- [x] **Step 1: Write failing full-trip and rejection tests**

```js
assert.deepEqual(
  materialized.transitStopTimes.map(({ stationId }) => stationId),
  [YONGSAN_ID, OKSU_ID, WANGSIMNI_ID, CHEONGNYANGNI_ID, CHUNCHEON_ID],
);
assert.throws(() => materializeKorailItxRows({ ...base, infoRows: oneDirection }), /both directions/);
assert.throws(() => materializeKorailItxRows({ ...base, trainNumbers: ["2001", "2002"] }), /train number set mismatch/);
assert.throws(() => materializeKorailItxRows({ ...base, infoRows: missingInteriorDeparture }), /planned timestamp missing/);
```

- [x] **Step 2: Run RED**

Run: `node --test tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs`

Expected: FAIL because 용산·옥수·왕십리 are dropped and completeness fields are absent.

- [x] **Step 3: Map every passenger stop without fake line membership**

Change the pack query to load all canonical stations by normalized name plus the existing Gyeongchun `line_sequence`. `selectPassengerStops` maps every passenger row through the all-station map, retains nullable Gyeongchun sequence, and rejects any unmapped row. The Gyeongchun-only subsequence remains monotonic.

- [x] **Step 4: Materialize directly from provider order**

Build `transitTrips` and `transitStopTimes` from each trip's sorted `trn_run_sn`. Derive `directionId` from its Gyeongchun subsequence, preserve the provider direction code, require plan endpoints to equal the first/last passenger stops, and require all applicable timestamps. Do not add outside stations to `station_lines`.

- [x] **Step 5: Enforce exact set and direction completeness**

```js
assertSameSet("roster/plan", rosterTrainNumbers, matchedPlanTrainNumbers);
assertSameSet("roster/info", rosterTrainNumbers, groupedInfoTrainNumbers);
assertSameSet("roster/materialized", rosterTrainNumbers, materializedTrainNumbers);
if (!directions.has("U") || !directions.has("D")) throw new Error("Korail ITX roster must include both directions");
```

- [x] **Step 6: Run GREEN and commit**

Run: `node --test tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs`

Expected: PASS.

```sh
git add tools/datapack/collect-korail-itx-cheongchun-timetable.mjs tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs
git commit -m "feat: enforce complete ITX trips"
```

### Task 3: 세 날짜 orchestration과 실패 artifact

**Files:**
- Modify: `tools/datapack/collect-korail-itx-cheongchun-timetable.mjs`
- Modify: `tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs`

**Interfaces:**
- Produces: `collectKorailItxCheongchunCompleteness({ serviceKey, serviceDates, packPath, fetchImpl, now, replay })`
- CLI: `--day8-date`, `--day7-date`, `--day9-date`, optional `--replay`, `--canonical-pack`, `--output`

- [x] **Step 1: Write failing orchestration tests**

Test that all three dates are called once, one incomplete direction makes the overall artifact `MISSING`, replay is `REPLAY_ONLY`, and a provider exception produces a redacted failure artifact.

```js
assert.deepEqual(artifact.selectedServiceDates, { "8": "20260715", "7": "20260718", "9": "20260719" });
assert.equal(artifact.admissionStatus, "MISSING");
assert.equal(artifact.admissionEligible, false);
assert.deepEqual(artifact.allowedConsumerIssues, ["#1400", "#2098", "#2099"]);
assert.equal(exitCode, 1);
assert.equal(savedArtifact.admissionStatus, "MISSING");
```

- [x] **Step 2: Run RED**

Run: `node --test tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs`

Expected: FAIL because the three-date API and failure artifact path do not exist.

- [x] **Step 3: Implement the smallest sequential orchestrator**

Validate dates once, process day codes in `8,7,9` order, record each failed day without substituting dates, and retain requested dates plus all per-day evidence. No parallel calls or retry layer beyond existing bounded provider retry.

- [x] **Step 4: Make CLI failure deterministic**

After validating `--output`, wrap collection in `try/catch`; on runtime failure write mode `0600` JSON with `admissionStatus: "MISSING"`, `admissionEligible: false`, a sanitized reason code, and `credentialRedacted: true`, then set `process.exitCode = 1`.

- [x] **Step 5: Run GREEN and commit**

Run: `node --test tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs`

Expected: PASS.

```sh
git add tools/datapack/collect-korail-itx-cheongchun-timetable.mjs tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs
git commit -m "feat: gate ITX completeness across service days"
```

### Task 4: Wiring contract와 live evidence

**Files:**
- Modify: `tools/datapack/itx-cheongchun-coverage-contract.json`
- Modify: `tools/datapack/itx-cheongchun-coverage-contract.test.mjs`
- Modify: `tools/datapack/nationwide-coverage-targets.json`
- Modify: `tools/datapack/report-coverage-gaps.mjs`
- Modify: `tools/datapack/source-candidates.json`
- Modify when generated: `tools/datapack/sources/korail-itx-cheongchun-*.json`

**Interfaces:**
- Consumes: three-date completeness artifact
- Produces: #2116 fail-closed coverage contract without #2094 wiring

- [x] **Step 1: Write failing contract tests**

```js
assert.equal(Object.hasOwn(contract.searchScopePolicy, "trainSearch"), false);
assert.equal(Object.hasOwn(itxTarget, "trainSearchCoverage"), false);
assert.equal(targets.railProductScope.trainSearchOnly.services.includes("ITX_CHEONGCHUN"), false);
assert.deepEqual(contract.allowedConsumerIssues, ["#1400", "#2098", "#2099"]);
assert.equal(contract.legacyDaejeonRowCount, 0);
assert.equal(contract.legacyYongsanDaejeonTripCount, 0);
```

- [x] **Step 2: Run RED**

Run: `node --test tools/datapack/itx-cheongchun-coverage-contract.test.mjs tools/datapack/datapack-tools.test.mjs`

Expected: FAIL on the existing `trainSearch`/`trainSearchCoverage` fields.

- [x] **Step 3: Remove only the direct train-search wiring and update validation**

Delete `searchScopePolicy.trainSearch`, the ITX target's `trainSearchCoverage`, and the corresponding `report-coverage-gaps.mjs` requirement. Keep `trainSearchOnly.services` unchanged because it already excludes `ITX_CHEONGCHUN`. Remove #2094 wording from the KORAIL source candidate.

- [x] **Step 4: Run the full local gate**

Run:

```sh
node --test \
  tools/datapack/collect-tago-itx-cheongchun-od.test.mjs \
  tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs \
  tools/datapack/itx-cheongchun-coverage-contract.test.mjs \
  tools/datapack/datapack-tools.test.mjs
```

Expected: PASS.

- [x] **Step 5: Run credential-safe live validation**

```sh
node --env-file=/Users/aquila/easysubway/.env tools/datapack/collect-korail-itx-cheongchun-timetable.mjs \
  --day8-date 20260715 \
  --day7-date 20260718 \
  --day9-date 20260719 \
  --canonical-pack apps/mobile/assets/datapacks/capital.sqlite.gz \
  --output /tmp/korail-itx-2116-completeness.json
```

Expected: exit 0 only when all completeness checks pass; otherwise a credential-free `MISSING` artifact and non-zero exit. Commit only sanitized evidence.

- [x] **Step 6: Commit**

```sh
git add tools/datapack/itx-cheongchun-coverage-contract.json \
  tools/datapack/itx-cheongchun-coverage-contract.test.mjs \
  tools/datapack/nationwide-coverage-targets.json \
  tools/datapack/report-coverage-gaps.mjs \
  tools/datapack/source-candidates.json \
  tools/datapack/sources/korail-itx-cheongchun-*.json
git commit -m "data: enforce ITX admission completeness"
```
