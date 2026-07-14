# ITX-청춘 timetable completeness 설계

## 목표와 범위

#2116은 현재 경춘선 ITX-청춘의 공식 station-level timetable을 `SUPPORTED`로 승격하기 위한 admission 계약이다. 직접 consumer는 #1400, #2098, #2099만 허용한다. 대전·과거 용산~대전 데이터와 #2094 기차검색 연결은 각각 0건이어야 한다. #2094의 별도 제품 요구사항은 이 계약의 consumer나 evidence source가 아니다.

`SUPPORTED`는 평일·토요일·일요일/공휴일의 세 service day가 모두 완전할 때만 가능하다. 하나라도 불완전하면 전체 상태를 `MISSING`으로 유지하며 LOCAL 시각, 추정값, 과거 데이터로 보완하지 않는다.

## 대표 날짜 입력

검증 실행은 아래 세 날짜를 `YYYYMMDD`로 반드시 명시한다.

- `dayCd 8`: 월요일~금요일 대표 날짜
- `dayCd 7`: 토요일 대표 날짜
- `dayCd 9`: 일요일 대표 날짜. 일요일은 `일요일·공휴일` service class의 재현 가능한 대표로 사용한다.

날짜는 코드·fixture·durable config에 운영 기본값으로 하드코딩하지 않는다. live admission의 세 날짜는 `Asia/Seoul` 실행일 기준 오늘부터 6일 뒤까지여야 한다. 세 입력값과 검증 시각을 artifact에 그대로 기록하고, 재검증은 새 대표 날짜 세 개와 새 artifact로 수행한다. 입력 누락, 요일·freshness 불일치, provider 오류, 빈 roster가 발생하면 실패하며 다른 날짜로 이동하지 않는다.

과거 artifact 재현과 단위 테스트는 명시적 `REPLAY` mode에서만 허용한다. replay artifact는 날짜별 completeness를 재현할 수 있지만 `admissionStatus: REPLAY_ONLY`, `admissionEligible: false`로 기록해 현재 release gate의 `SUPPORTED` 근거가 될 수 없다. 자동 날짜 선택 로직은 두지 않으므로 주말·월말·연말 경계는 유효한 달력 날짜·요일·6일 window 테스트로 다룬다.

## 공식 roster 수집

각 날짜는 다음 흐름을 독립 실행한다.

1. roster 탐색용 역은 canonical pack의 현재 경춘선 역 집합과 TAGO 공식 열차역 카탈로그의 교집합으로 정한다. TAGO 카탈로그에 없는 canonical 역은 `excludedCanonicalStations`에 사유와 함께 기록하며 조용히 누락하지 않는다. 교집합이 비어 있거나 provider 역 이름이 둘 이상 mapping되는 경우 `MISSING`으로 판정한다.
2. TAGO `GetStrtpntAlocFndTrainInfo`를 ITX-청춘 등급 코드 `09`로 roster 탐색 역의 모든 순서 있는 OD 쌍에 대해 조회한다.
3. 각 OD 응답의 `totalCount`까지 전 페이지를 수집하고 당일 열차번호를 합집합·중복 제거해 공식 roster를 만든다.
4. KORAIL `codes2`, `travelerTrainRunPlan2`, `travelerTrainRunInfo2`도 당일 범위를 전 페이지 수집한다. `mrnt_cd=경춘선` 이외의 운행정보는 거부한다.
5. roster 열차번호로 KORAIL 계획과 운행정보를 결합하고, 계획의 실제 시발·종착 및 운행정보의 방향·전체 정차 순서를 확정한다.
6. trip materialization은 탐색 역 집합과 분리한다. 용산·옥수·왕십리 등 경춘선 밖을 포함한 KORAIL 여객 정차 row 전부를 canonical station에 mapping하며, 하나라도 mapping하지 못하면 `MISSING`으로 판정한다.

roster 탐색 역의 모든 OD를 조회하는 방식은 고정 시종착 목록보다 호출 수가 많지만 현재 시·종착 변형을 누락하지 않는다. 고정 OD 목록은 시간이 지나면 새 변형을 놓치므로 채택하지 않는다. 열차번호 범위 추정도 공식 roster가 아니므로 사용하지 않는다.

KORAIL catalog상 `travelerTrainRunInfo2`의 조회 범위는 전일까지다. 따라서 오늘부터 6일 이내인 현재 admission 날짜에서 이 operation이 0건이면 과거 날짜로 이동하지 않고 `OFFICIAL_RUN_INFO_EMPTY`로 `MISSING`을 유지한다. 과거 날짜의 정차 순서·빈 시각 evidence는 source capability 판정에만 쓰며 현재 admission을 열지 않는다. provider가 현재 계획 정차시각을 제공하거나 다른 공식 station-level operation이 확인될 때 새 대표 날짜로 재검증한다.

## 완전성 판정

날짜별 `SUPPORTED` 조건은 모두 충족해야 한다.

- TAGO roster, KORAIL plan, KORAIL info group, materialized trip의 열차번호 집합이 정확히 같다.
- `U`, `D` 양방향이 모두 존재한다.
- roster에서 관측한 모든 현재 시발·종착 조합이 plan과 trip에 존재한다.
- 각 trip에 열차번호, 방향, service day, 시발, 종착이 있다.
- 각 trip은 용산~춘천을 포함한 모든 여객 정차역을 `trn_run_sn` 순서로 보존하고 누락·중복이 없다. 경춘선에 속한 연속 구간은 canonical line 순서와도 일치한다.
- 시발은 계획 출발 시각, 종착은 계획 도착 시각, 중간 정차는 계획 도착·출발 시각이 모두 존재한다. 시발의 도착 또는 종착의 출발처럼 의미 없는 값만 예외로 한다.
- 시각은 `Asia/Seoul` service date 또는 바로 다음 날 범위이며 단조 증가한다.
- roster-filtered admission 결과에서 대전역, 대전 노선, 과거 용산~대전 trip/row가 0건이다.
- tracked manifest·coverage contract의 실제 wiring은 #1400, #2098, #2099만 허용하며 #2094 연결은 0건이다.

열차번호 집합 불일치, 단방향, 일부 편성, 일부 정차역, 일부 시각, 일부 날짜 중 하나라도 발견되면 해당 날짜와 전체 admission을 `MISSING`으로 판정한다. 시각이 모두 비어 있는 현재 provider 응답도 `MISSING`이며 별도 성공 상태로 승격하지 않는다.

## artifact 계약

상위 artifact는 다음 정보를 credential 없이 기록한다.

- `observedAt`, `timezone: Asia/Seoul`, `validationMode`
- `selectedServiceDates`: `{ "8": "YYYYMMDD", "7": "YYYYMMDD", "9": "YYYYMMDD" }`
- `admissionStatus`, `admissionEligible`
- 날짜별 provider operation, page 수, row 수, sanitized response hash
- 날짜별 canonical 역 수, roster 탐색 역 수, 제외된 canonical 역과 사유
- 날짜별 `expectedOdCount`, `completedOdCount`, `failedOdCount`, `stationSetHash`, 정렬된 `odMatrixHash`
- 날짜별 roster/train plan/train info/materialized train-number 집합과 불일치 집합
- 날짜별 방향 집합, 시발·종착 조합, trip 수, 정차 row 수, 시각 누락 수
- 날짜별 completeness 상태와 실패 reason code
- 전체 `materialization.status`
- `allowedConsumerIssues`: `["#1400", "#2098", "#2099"]`
- `legacyDaejeonRowCount: 0`, `legacyYongsanDaejeonTripCount: 0`
- 입력과 결과를 포함한 결정적 `evidenceHash`, `credentialRedacted: true`

정렬된 교집합 탐색 역이 `n`개면 `expectedOdCount`는 `n * (n - 1)`이다. admission에는 `completedOdCount === expectedOdCount`, `failedOdCount === 0` 및 실행 전 결정한 station set·OD matrix hash 일치가 필요하다.

CLI 인자와 output 경로 검증이 끝난 뒤 발생한 provider HTTP/schema/result code 오류, roster 0건, completeness 실패는 해당 날짜를 `MISSING`으로 기록하되 나머지 두 날짜를 대체 없이 독립 검증한다. 세 날짜의 sanitized 진단을 포함한 artifact를 저장한 다음 non-zero로 종료한다. 성공한 세 날짜만 `admissionStatus: SUPPORTED`와 exit 0을 허용한다.

## 구현 경계

기존 `fetchAll`, KORAIL parser와 canonical pack reader를 재사용한다. 전체 trip의 stop_times는 collector 안에서 `trn_run_sn` 순서로 만들고, 경춘선 밖 역에 거짓 `station_line` membership을 추가하지 않는다. 기존 경춘선 line order는 topology projection 구간 검증에만 사용한다. 세 날짜 실행과 집합 비교를 담당하는 작은 orchestration 계층만 추가하며 새 runtime dependency나 product fallback은 추가하지 않는다.

현재 계약의 `trainSearch` 및 `trainSearchCoverage` 직접 연결 문구를 제거한다. artifact는 허용 scope만 선언한다. 실제 wiring 테스트는 `itx-cheongchun-coverage-contract.json`에 `trainSearch`가 없고, `nationwide-coverage-targets.json`의 ITX entry에 `trainSearchCoverage`가 없으며 `trainSearchOnly.services`가 `ITX_CHEONGCHUN`을 포함하지 않는지 검증한다.

최종 live CLI는 세 날짜가 모두 없으면 실행되지 않아야 한다.

```sh
node --env-file=/Users/aquila/easysubway/.env tools/datapack/collect-korail-itx-cheongchun-timetable.mjs \
  --day8-date 20260715 \
  --day7-date 20260718 \
  --day9-date 20260719 \
  --canonical-pack apps/mobile/assets/datapacks/capital.sqlite.gz \
  --output /tmp/korail-itx-2116-completeness.json
```

과거 증거 재현은 같은 명령에 `--replay`를 명시하며, 이 경우 현재 admission을 열 수 없다.

로컬 검증 명령은 다음과 같다.

```sh
node --test \
  tools/datapack/collect-tago-itx-cheongchun-od.test.mjs \
  tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs \
  tools/datapack/itx-cheongchun-coverage-contract.test.mjs
```

## 테스트

- 세 날짜 입력 누락, 잘못된 달력 날짜, `8/7/9` 요일 불일치 거부
- KST 오늘~6일 admission window와 과거/7일 이후 거부, `REPLAY`의 admission 불가
- 토요일·일요일 경계, 월말, 윤년 2월 말, 연말 날짜 검증
- 세 service day 독립 수집과 artifact 날짜 고정
- provider 오류·빈 roster 발생 시 날짜 대체 없이 실패
- 모든 operation의 full pagination, roster deduplication, OD count·station set/OD matrix hash 검증
- canonical 경춘선과 TAGO 열차역 카탈로그 교집합 및 제외역 증거 검증
- 양방향·모든 시종착 변형 완전 성공
- 한 방향 누락, 일부 편성, plan/info/trip 열차번호 집합 불일치 거부
- 경춘선 밖 여객 정차역을 포함한 용산~춘천 전체 trip 보존
- 일부 정차역, canonical mapping 누락, 중복·역순 정차, 일부 계획 시각 누락 거부
- 한 날짜만 실패해도 전체 `MISSING`
- runtime 실패 시 `MISSING` artifact 저장과 CLI non-zero
- 대전/과거 용산~대전 row와 실제 manifest·contract의 #2094 consumer 연결 0건
- artifact와 로그에 credential이 없는지 검증
