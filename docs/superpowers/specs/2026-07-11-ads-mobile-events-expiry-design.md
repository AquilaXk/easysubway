# 광고 무식별 이벤트·만료 설계 (#1971)

## 배경

#1762 제품 동등성 트래커 아래 #1771은 자체 서빙 비개인화 광고의 공개 API, 일별 집계 테이블, 모바일 배너 기준선을 만들었다. 현재 backend는 `POST /api/ads/events`를 제공하지만 mobile은 이벤트를 보내지 않으며, 활성 소재 응답에 종료 시각이 없어 이미 표시된 배너가 운영 종료 뒤에도 남을 수 있다. #1971은 기존 개인정보 경계를 유지하면서 이 두 간극만 닫는다.

## 결정

기존 `AdRepository`와 `ActiveAdBanner`를 최소 확장한다. 별도 SDK, 계측 계층, 영속 큐는 만들지 않는다.

### Backend 응답

- `GET /api/ads/active`의 `data`에 nullable `endsAt`을 추가한다.
- 값이 있으면 UTC RFC 3339 문자열(`...Z`)로 반환한다. `null`은 예약된 종료 시각이 없다는 뜻이다.
- `endsAt`은 ETag fingerprint에 계속 포함되어 종료 시각 변경이 캐시 검증에 반영된다.
- 기존 `POST /api/ads/events`와 `{placement, creativeId, eventType}` 계약 및 `204 No Content` 응답을 재사용한다.

### Mobile 모델과 전송

- `AdCreative`에 nullable UTC `DateTime endsAt`을 추가한다. 잘못된 값은 소재 전체를 invalid로 보고 기존처럼 숨긴다.
- `AdRepository`에 `recordEvent(placement, creativeId, eventType)`를 추가해 아래 JSON만 전송한다.

```json
{"placement":"route-result-bottom","creativeId":"creative-1","eventType":"IMPRESSION"}
```

- payload에 사용자·기기·세션 식별자, 시각, 위치, 화면 이동 기록을 넣지 않는다.
- impression은 이미지 decode가 끝나고 현재 generation의 배너가 실제 frame에 render된 뒤, 표시된 `(placement, creativeId)` 생명주기당 한 번만 fire-and-forget으로 보낸다. 이 생명주기는 render부터 만료, reload, widget 교체 또는 `dispose`로 배너가 제거될 때까지다.
- click은 사용자의 명시적 tap마다 fire-and-forget으로 보내며, 전송 성공 여부와 무관하게 기존 외부 브라우저 이동을 진행한다.
- 이벤트 실패는 광고 표시와 landing 동작에 영향을 주지 않는다.

### `204 No Content`

`ApiClient`는 성공한 204의 빈 body를 JSON decode하지 않고 `ApiResponse(statusCode: 204, jsonBody: null)`로 반환한다. 다른 성공 응답의 JSON 처리와 오류 매핑은 바꾸지 않는다. `AdRepository`는 204를 이벤트 전송 완료로 취급하지만 반환값을 UI 상태로 노출하지 않는다.

### 만료 lifecycle

- fetch 완료 시 `endsAt <= now`이면 배너를 render하지 않는다.
- 미래 `endsAt`이 있으면 현재 generation에 Timer 하나를 예약한다.
- Timer가 발화하면 `_creative`와 `_image`를 즉시 비워 `SizedBox.shrink()`로 collapse한다. 자동 refetch는 하지 않는다.
- reload, widget 교체, generation 변경, `dispose` 때 기존 Timer를 cancel한다. `endsAt == null`이면 Timer를 만들지 않는다.
- 늦게 도착한 fetch, decode, Timer callback은 기존 generation/mounted guard를 통과할 때만 state를 바꾼다.

## 개인정보와 실패 경계

스토어 계약은 광고 이벤트 사용 사실만 다음처럼 갱신한다.

- `measurementEvents: true`
- `collectedData: none` (`collectedDataTypeIds: []`)
- `adId: false`
- `thirdPartyAdSdk: false`
- `tracking: false`

집계는 backend의 날짜·placement·creative·event type별 count뿐이다. mobile은 이벤트를 저장하지 않고 식별자를 생성하거나 읽지 않는다. 실패 시 사용자 오류를 표시하지 않으며 retry, backoff, offline queue, 로컬 저장을 하지 않는다. 서버도 기존 일별 count 외 원본 event를 보관하지 않는다.

## 대안과 기각 이유

1. 별도 `AdEventRepository`나 analytics service를 둔다: 이벤트 종류가 impression/click 두 개이고 기존 `AdRepository`와 같은 API client·광고 계약을 쓰므로 추상화와 wiring만 늘어난다.
2. 광고/analytics SDK 또는 식별자 기반 dedupe를 쓴다: `AD_ID`·제3자 SDK·tracking 없음이라는 #1771 경계를 깨고, 일별 익명 count라는 목적보다 넓다.

## TDD와 증거

1. Backend test를 먼저 실패시켜 `endsAt`의 UTC `Z` 응답, nullable 값, 기존 event 204·무식별 집계를 고정한다.
2. `ApiClient` test로 204 빈 body가 decode 오류 없이 성공하는 RED→GREEN을 남긴다.
3. `AdRepository` test로 `endsAt` parsing, 정확한 세 필드 payload, 204, network/timeout 실패 무시를 고정한다.
4. `ActiveAdBanner` widget test로 실제 render 전 impression 없음, render 후 생명주기당 1회, click fire-and-forget, 만료 즉시 collapse, reload/dispose Timer cancel을 검증한다.
5. Repository contract에서 event endpoint의 이 무식별 사용만 허용하고 SDK·`AD_ID`·추가 식별자·tracking 금지를 유지한다. 관련 backend/mobile focused test와 release 개인정보 계약 검사를 증거로 남긴다.

실제 production 광고 소재·event 집계 E2E는 Play Store 게시 전 검증할 수 없다. Owner 승인에 따라 code release gate에서는 deferred로 기록하고, 게시 후 실제 앱의 impression 1회, click, 종료 시 collapse, 일별 count를 확인한다.

## 범위 밖

- 이벤트 재시도, batch, offline queue, 로컬 저장, 사용자/기기/세션 식별자
- 제3자 광고·analytics SDK, 개인화, attribution, cross-app/web tracking
- 새 DB migration, 원본 event 로그, 실시간 dashboard, admin UI 변경
- 광고 소재 cache/refetch 정책 변경, placement 추가, landing fallback
- Play Store 게시와 게시 후 실제 E2E 실행 자체
