# ITX-청춘 timetable completeness 설계

## 목표와 범위

#2116은 현재 경춘선 ITX-청춘의 공식 station-level timetable을 `SUPPORTED`로 승격하기 위한 admission 계약이다. 직접 consumer는 #1400, #2098, #2099만 허용한다. 대전·과거 용산~대전 데이터와 #2094 기차검색 연결은 각각 0건이어야 한다. #2094의 별도 제품 요구사항은 이 계약의 consumer나 evidence source가 아니다.

`SUPPORTED`는 평일·토요일·일요일/공휴일의 세 service day가 모두 완전할 때만 가능하다. 하나라도 불완전하면 전체 상태를 `MISSING`으로 유지하며 LOCAL 시각, 추정값, 과거 데이터로 보완하지 않는다.

## 대표 날짜 입력

검증 실행은 아래 세 날짜를 `YYYYMMDD`로 반드시 명시한다.

- `dayCd 8`: 월요일~금요일 대표 날짜
- `dayCd 7`: 토요일 대표 날짜
- `dayCd 9`: 일요일 대표 날짜. 일요일은 `일요일·공휴일` service class의 재현 가능한 대표로 사용한다.

날짜는 코드·fixture·durable config에 운영 기본값으로 하드코딩하지 않는다. 세 입력값과 `Asia/Seoul` 기준 검증 시각을 artifact에 그대로 기록한다. 재검증은 새 대표 날짜 세 개와 새 artifact로 수행한다. 입력 누락, 요일 불일치, provider 오류, 빈 roster가 발생하면 실패하며 다른 날짜로 이동하지 않는다.

과거 artifact 재현과 단위 테스트도 같은 명시적 날짜 입력 경로를 사용한다. 자동 날짜 선택 로직은 두지 않으므로 주말·월말·연말 경계는 유효한 달력 날짜와 요일 검증 테스트로 다룬다.

## 공식 roster 수집

각 날짜는 다음 흐름을 독립 실행한다.

1. canonical pack의 현재 경춘선 역 집합과 검증된 TAGO station ID mapping을 읽는다. canonical 역 하나라도 mapping이 없으면 `MISSING`으로 판정한다.
2. TAGO `GetStrtpntAlocFndTrainInfo`를 ITX-청춘 등급 코드 `09`로 현재 canonical 역의 모든 순서 있는 OD 쌍에 대해 조회한다.
3. 각 OD 응답의 `totalCount`까지 전 페이지를 수집하고 당일 열차번호를 합집합·중복 제거해 공식 roster를 만든다.
4. KORAIL `codes2`, `travelerTrainRunPlan2`, `travelerTrainRunInfo2`도 당일 범위를 전 페이지 수집한다. `mrnt_cd=경춘선` 이외의 운행정보는 거부한다.
5. roster 열차번호로 KORAIL 계획과 운행정보를 결합하고, 계획의 실제 시발·종착 및 운행정보의 방향·전체 정차 순서를 확정한다.

모든 canonical OD를 조회하는 방식은 고정 시종착 목록보다 호출 수가 많지만 현재 시·종착 변형을 누락하지 않는다. 고정 OD 목록은 시간이 지나면 새 변형을 놓치므로 채택하지 않는다. 열차번호 범위 추정도 공식 roster가 아니므로 사용하지 않는다.

## 완전성 판정

날짜별 `SUPPORTED` 조건은 모두 충족해야 한다.

- TAGO roster, KORAIL plan, KORAIL info group, materialized trip의 열차번호 집합이 정확히 같다.
- `U`, `D` 양방향이 모두 존재한다.
- roster에서 관측한 모든 현재 시발·종착 조합이 plan과 trip에 존재한다.
- 각 trip에 열차번호, 방향, service day, 시발, 종착이 있다.
- 각 trip의 모든 여객 정차역이 provider 순서와 canonical line 순서에 맞고 누락·중복이 없다.
- 시발은 계획 출발 시각, 종착은 계획 도착 시각, 중간 정차는 계획 도착·출발 시각이 모두 존재한다. 시발의 도착 또는 종착의 출발처럼 의미 없는 값만 예외로 한다.
- 시각은 `Asia/Seoul` service date 또는 바로 다음 날 범위이며 단조 증가한다.
- 대전역, 대전 노선, 과거 용산~대전 trip/row가 0건이다.
- consumer 연결 수는 #1400, #2098, #2099가 각각 계약대로 존재하고 #2094는 0건이다.

열차번호 집합 불일치, 단방향, 일부 편성, 일부 정차역, 일부 시각, 일부 날짜 중 하나라도 발견되면 해당 날짜와 전체 admission을 `MISSING`으로 판정한다. 시각이 모두 비어 있는 현재 provider 응답도 `MISSING`이며 별도 성공 상태로 승격하지 않는다.

## artifact 계약

상위 artifact는 다음 정보를 credential 없이 기록한다.

- `observedAt`, `timezone: Asia/Seoul`
- `selectedServiceDates`: `{ "8": "YYYYMMDD", "7": "YYYYMMDD", "9": "YYYYMMDD" }`
- 날짜별 provider operation, page 수, row 수, sanitized response hash
- 날짜별 roster/train plan/train info/materialized train-number 집합과 불일치 집합
- 날짜별 방향 집합, 시발·종착 조합, trip 수, 정차 row 수, 시각 누락 수
- 날짜별 completeness 상태와 실패 reason code
- 전체 `materialization.status`
- `consumerCounts`: `{ "1400": 1, "2098": 1, "2099": 1, "2094": 0 }`
- `legacyDaejeonRowCount: 0`, `legacyYongsanDaejeonTripCount: 0`
- 입력과 결과를 포함한 결정적 `evidenceHash`, `credentialRedacted: true`

provider HTTP/schema/result code 실패나 roster 0건은 sanitized 진단을 남기고 프로세스를 실패시킨다. 실패 artifact를 `SUPPORTED` artifact로 저장하지 않는다.

## 구현 경계

기존 `fetchAll`, KORAIL parser, canonical pack reader, trip reconstruction을 재사용한다. 세 날짜 실행과 집합 비교를 담당하는 작은 orchestration 계층만 추가하며 새 runtime dependency나 product fallback은 추가하지 않는다. 현재 계약의 `trainSearch` 및 `trainSearchCoverage` 직접 연결 문구는 제거하고 #2094 consumer 0건을 테스트로 고정한다.

최종 live CLI는 세 날짜가 모두 없으면 실행되지 않아야 한다.

```sh
node --env-file=/Users/aquila/easysubway/.env tools/datapack/collect-korail-itx-cheongchun-timetable.mjs \
  --day8-date 20260715 \
  --day7-date 20260718 \
  --day9-date 20260719 \
  --canonical-pack apps/mobile/assets/datapacks/capital.sqlite.gz \
  --output /tmp/korail-itx-2116-completeness.json
```

로컬 검증 명령은 다음과 같다.

```sh
node --test \
  tools/datapack/collect-korail-itx-cheongchun-timetable.test.mjs \
  tools/datapack/itx-cheongchun-coverage-contract.test.mjs
```

## 테스트

- 세 날짜 입력 누락, 잘못된 달력 날짜, `8/7/9` 요일 불일치 거부
- 토요일·일요일 경계, 월말, 윤년 2월 말, 연말 날짜 검증
- 세 service day 독립 수집과 artifact 날짜 고정
- provider 오류·빈 roster 발생 시 날짜 대체 없이 실패
- 모든 operation의 full pagination과 roster deduplication
- 양방향·모든 시종착 변형 완전 성공
- 한 방향 누락, 일부 편성, plan/info/trip 열차번호 집합 불일치 거부
- 일부 정차역, 중복·역순 정차, 일부 계획 시각 누락 거부
- 한 날짜만 실패해도 전체 `MISSING`
- 대전/과거 용산~대전 row와 #2094 consumer 연결 0건
- artifact와 로그에 credential이 없는지 검증
