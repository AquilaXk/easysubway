# Ads Mobile Events and Expiry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 활성 광고 응답의 UTC 만료 시각을 모바일까지 전달하고, 식별자 없는 impression/click을 전송하며, 현재 배너를 종료 시각에 즉시 접는다.

**Architecture:** 기존 backend `AdPublicController.AdResponse`, mobile `ApiClient`, `AdRepository`, `ActiveAdBanner`만 최소 확장한다. 이벤트는 기존 `/api/ads/events`에 fire-and-forget으로 보내고, 배너 상태는 기존 generation guard에 Timer 하나와 생명주기당 impression boolean 하나만 더해 관리한다.

**Tech Stack:** Java 21, Spring Boot, MockMvc, Flutter/Dart, `dart:io` `HttpClient`, Flutter widget tests, Node.js repository contract tests

## Global Constraints

- `GET /api/ads/active`의 `data.endsAt`은 nullable이며, 값이 있으면 UTC RFC 3339 `...Z` 문자열이다.
- 기존 `POST /api/ads/events` 계약은 `{placement, creativeId, eventType}` 세 필드와 `204 No Content`를 그대로 사용한다.
- payload에 사용자·기기·세션 식별자, 시각, 위치, 화면 이동 기록을 추가하지 않는다.
- impression은 이미지 decode와 현재 generation의 실제 frame render 뒤 `(placement, creativeId)` 배너 생명주기당 한 번만 보낸다.
- click은 명시적 tap마다 보내며 이벤트 성공 여부와 무관하게 기존 외부 브라우저 이동을 실행한다.
- 이벤트 실패는 조용히 무시하고 retry, backoff, batch, offline queue, 로컬 저장을 추가하지 않는다.
- 미래 `endsAt`에는 현재 generation의 Timer 하나만 두고, 만료·reload·widget 교체·generation 변경·`dispose`에서 cancel 또는 폐기한다. 자동 refetch는 하지 않는다.
- 늦은 fetch, decode, post-frame callback, Timer callback은 `mounted`와 generation guard를 통과할 때만 상태 또는 impression 생명주기를 바꾼다.
- 새 abstraction, dependency, 광고/analytics SDK, `AD_ID`, 식별자, tracking, DB migration, 원본 event log를 추가하지 않는다.
- 개인정보 계약은 `measurementEvents: true`, `collectedDataTypeIds: []`, `adId: false`, `thirdPartyAdSdk: false`, `tracking: false`를 유지한다.
- 루트 `README.md`는 변경하지 않는다.
- production 광고 소재·event 집계 E2E는 code release 완료 조건이 아니다. owner 승인으로 deferred를 기록하고 Play Store 게시 후 impression 1회, click, 종료 collapse, 일별 count를 확인한다.

## File Structure

- `backend/src/main/java/com/easysubway/ads/adapter/in/web/AdPublicController.java`: 공개 활성 소재 DTO에 UTC `endsAt`을 노출한다.
- `backend/src/test/java/com/easysubway/ads/adapter/in/web/AdPublicControllerTest.java`: `endsAt`의 `Z`, null, ETag 반영과 기존 무식별 204 집계를 고정한다.
- `apps/mobile/lib/core/network/api_client.dart`: 성공한 204 빈 body의 JSON decode를 건너뛴다.
- `apps/mobile/test/core/network/api_client_test.dart`: 빈 204가 `jsonBody: null`로 성공하는 계약을 고정한다.
- `apps/mobile/lib/features/ads/ad_repository.dart`: `AdCreative.endsAt`, UTC parsing, 두 event type과 세 필드 POST를 소유한다.
- `apps/mobile/test/features/ads/ad_repository_test.dart`: parsing, exact payload, 204, network/timeout 무시를 고정한다.
- `apps/mobile/lib/features/ads/active_ad_banner.dart`: render 후 impression, tap별 click, generation별 expiry Timer를 관리한다.
- `apps/mobile/test/features/ads/active_ad_banner_test.dart`: render/event/expiry/reload/dispose lifecycle을 widget test로 고정한다.
- `apps/mobile/release/store-privacy-inventory.json`: 무식별 광고 measurement 사용 사실만 선언한다.
- `apps/mobile/release/store-submission-readiness.json`: code evidence와 게시 후 owner E2E deferred 경계를 기록한다.
- `tools/ci/repository-contract.test.mjs`: 허용된 유일한 mobile event sender와 무SDK·무AD_ID·무tracking 계약을 검증한다.

---

### Task 1: Backend active 응답 `endsAt`

**Files:**
- Modify: `backend/src/test/java/com/easysubway/ads/adapter/in/web/AdPublicControllerTest.java:45-109`
- Modify: `backend/src/main/java/com/easysubway/ads/adapter/in/web/AdPublicController.java:66-96`

**Interfaces:**
- Consumes: 기존 `AdCreative.endsAt(): LocalDateTime`, UTC로 저장·조회되는 `ad_creatives.ends_at`, 기존 `etagFor(AdResponse, AdCreative)` fingerprint
- Produces: `AdResponse(..., Instant endsAt)`와 JSON `data.endsAt: String?`; non-null 값은 UTC `Z`, null 값은 JSON null

- [ ] **Step 1: non-null UTC, nullable 값, ETag 변경을 고정하는 failing test를 작성한다**

`returnsActiveCreativeWithoutIdentifiers`에 정확한 UTC 기대값을 만들고 `endsAt` assertion을 추가한다.

```java
LocalDateTime endsAt = now.plusHours(1).withNano(0);
insertCreative("active", "route-result-bottom", now.minusHours(1), endsAt, true);

// 기존 response assertions 뒤
.andExpect(jsonPath("$.data.endsAt")
    .value(endsAt.toInstant(ZoneOffset.UTC).toString()))
```

nullable 종료 시각은 별도 test로 JSON null을 고정한다.

```java
@Test
@DisplayName("예약 종료 시각이 없으면 endsAt을 null로 반환한다")
void returnsNullEndsAtWithoutScheduledExpiry() throws Exception {
    LocalDateTime now = LocalDateTime.now(ZoneOffset.UTC);
    insertPlacement("route-result-bottom");
    insertCreative("open-ended", "route-result-bottom", now.minusHours(1), null, true);

    mockMvc.perform(get("/api/ads/active")
            .param("placement", "route-result-bottom"))
        .andExpect(status().isOk())
        .andExpect(jsonPath("$.data.endsAt").value(org.hamcrest.Matchers.nullValue()));
}
```

기존 ETag test는 image URL 대신 `ends_at`만 변경하여 종료 시각이 fingerprint에 남는 계약을 직접 검증한다.

```java
LocalDateTime now = LocalDateTime.now(ZoneOffset.UTC).withNano(0);
jdbcTemplate.update("""
    UPDATE ad_creatives
    SET ends_at=?
    WHERE id=?
    """, now.plusHours(2), "active");

mockMvc.perform(get("/api/ads/active")
        .param("placement", "route-result-bottom")
        .header("If-None-Match", first.getResponse().getHeader("ETag")))
    .andExpect(status().isOk())
    .andExpect(header().string(
        "ETag",
        org.hamcrest.Matchers.not(first.getResponse().getHeader("ETag"))))
    .andExpect(jsonPath("$.data.endsAt")
        .value(now.plusHours(2).toInstant(ZoneOffset.UTC).toString()));
```

- [ ] **Step 2: backend focused test를 실행해 RED를 확인한다**

Run: `backend/gradlew test --tests com.easysubway.ads.adapter.in.web.AdPublicControllerTest`

Expected: FAIL — `$.data.endsAt`이 존재하지 않아 non-null 또는 null assertion이 실패한다. 기존 event test의 `204 No Content`와 일별 `event_count=1` assertion은 그대로 유지된다.

- [ ] **Step 3: `AdResponse`가 nullable UTC `Instant`를 직렬화하도록 최소 구현한다**

`AdPublicController.java`에 `Instant`와 `ZoneOffset` import를 추가하고 record의 마지막 필드와 factory만 확장한다.

```java
import java.time.Instant;
import java.time.ZoneOffset;
```

```java
record AdResponse(
    String placement,
    String creativeId,
    String imageUrl,
    String landingUrl,
    String advertiserName,
    String altText,
    Instant endsAt
) {
    static AdResponse from(AdCreative creative) {
        return new AdResponse(
            creative.placementId(),
            creative.id(),
            creative.imageUrl(),
            creative.landingUrl(),
            creative.advertiserName(),
            creative.altText(),
            creative.endsAt() == null
                ? null
                : creative.endsAt().toInstant(ZoneOffset.UTC));
    }
}
```

`etagFor`의 기존 `String.valueOf(creative.endsAt())` 항목은 삭제하거나 중복 추가하지 않고 그대로 둔다.

- [ ] **Step 4: backend focused test를 다시 실행해 GREEN을 확인한다**

Run: `backend/gradlew test --tests com.easysubway.ads.adapter.in.web.AdPublicControllerTest`

Expected: PASS — non-null `endsAt`은 `Z` 문자열, 예약 종료가 없으면 null이고, 종료 시각만 바뀌어도 ETag가 달라지며 event endpoint는 계속 204와 무식별 일별 count를 반환한다.

- [ ] **Step 5: Task 1만 커밋한다**

```bash
git add backend/src/main/java/com/easysubway/ads/adapter/in/web/AdPublicController.java backend/src/test/java/com/easysubway/ads/adapter/in/web/AdPublicControllerTest.java
git commit -m "feat(ads): 활성 소재 종료 시각 공개 (#1971)"
```

---

### Task 2: `ApiClient` 204와 `AdRepository` event/`endsAt`

**Files:**
- Modify: `apps/mobile/test/core/network/api_client_test.dart:55-107`
- Modify: `apps/mobile/lib/core/network/api_client.dart:118-137`
- Modify: `apps/mobile/test/features/ads/ad_repository_test.dart:8-281`
- Modify: `apps/mobile/lib/features/ads/ad_repository.dart:3-115`

**Interfaces:**
- Consumes: Task 1의 `data.endsAt: String?`, `ApiClient.postJson(String, {required Map<String, Object?> body, Map<String, String> headers})`
- Produces: `AdCreative.endsAt: DateTime?`(non-null이면 `isUtc == true`), `AdEventType.impression`, `AdEventType.click`, `Future<void> AdRepository.recordEvent(AdPlacement placement, String creativeId, AdEventType eventType)`

- [ ] **Step 1: 성공한 빈 204가 decode되지 않는 failing test를 작성한다**

`api_client_test.dart`에 실제 local `HttpServer`를 쓰는 test를 추가한다.

```dart
test('ApiClient는 성공한 204 빈 body를 JSON decode하지 않는다', () async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(server.close);
  server.listen((request) async {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  });
  final client = ApiClient(
    baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
  );

  final response = await client.postJson(
    '/api/ads/events',
    body: const {
      'placement': 'route-result-bottom',
      'creativeId': 'creative-1',
      'eventType': 'IMPRESSION',
    },
  );

  expect(response.statusCode, HttpStatus.noContent);
  expect(response.jsonBody, isNull);
  expect(response.isSuccess, isTrue);
});
```

- [ ] **Step 2: ApiClient focused test를 실행해 RED를 확인한다**

Run from `apps/mobile`: `flutter test test/core/network/api_client_test.dart --plain-name 'ApiClient는 성공한 204 빈 body를 JSON decode하지 않는다'`

Expected: FAIL — 빈 문자열을 `jsonDecode`하다 `ApiException`이 발생하고 cause가 `FormatException: Unexpected end of input`이다.

- [ ] **Step 3: 204에서 null response를 반환하는 최소 구현을 작성한다**

`_requestJson`의 non-success 분기 다음, `_decodeJson` 호출 전에 이 분기를 추가한다.

```dart
if (response.statusCode == HttpStatus.noContent) {
  return ApiResponse(
    statusCode: response.statusCode,
    jsonBody: null,
    etag: etag,
  );
}
```

- [ ] **Step 4: ApiClient focused test를 실행해 GREEN을 확인한다**

Run from `apps/mobile`: `flutter test test/core/network/api_client_test.dart --plain-name 'ApiClient는 성공한 204 빈 body를 JSON decode하지 않는다'`

Expected: PASS — status 204, `jsonBody == null`, `isSuccess == true`이다. 다른 성공 JSON과 기존 오류 mapping 코드는 바뀌지 않는다.

- [ ] **Step 5: repository UTC parsing과 exact event POST의 failing tests를 작성한다**

`_creativeData`에 nullable `endsAt`을 항상 포함한다.

```dart
Map<String, Object?> _creativeData({
  String placement = 'route-result-bottom',
  String creativeId = 'creative-1',
  String imageUrl = 'https://cdn.easysubway.app/ad.png',
  String landingUrl = 'https://advertiser.example/campaign',
  String advertiserName = '이지상점',
  String altText = '이지상점 여름 할인',
  Object? endsAt = '2026-07-12T12:34:56Z',
}) => {
  'placement': placement,
  'creativeId': creativeId,
  'imageUrl': imageUrl,
  'landingUrl': landingUrl,
  'advertiserName': advertiserName,
  'altText': altText,
  'endsAt': endsAt,
};
```

정상 mapping test에 아래 assertion을 추가하고 null/invalid 계약을 별도로 고정한다.

```dart
expect(creative?.endsAt, DateTime.utc(2026, 7, 12, 12, 34, 56));
expect(creative?.endsAt?.isUtc, isTrue);
```

```dart
test('endsAt null은 허용하고 malformed 또는 local 시각은 소재 전체를 숨긴다', () async {
  final noExpiry = await AdRepository(
    _StubApiClient(_response(200, data: _creativeData(endsAt: null))),
  ).fetchActive(AdPlacement.routeResultBottom);
  expect(noExpiry, isNotNull);
  expect(noExpiry?.endsAt, isNull);

  for (final invalid in <Object?>['not-a-date', '2026-07-12T12:34:56', 1, true]) {
    final creative = await AdRepository(
      _StubApiClient(_response(200, data: _creativeData(endsAt: invalid))),
    ).fetchActive(AdPlacement.routeResultBottom);
    expect(creative, isNull, reason: 'endsAt=$invalid');
  }
});
```

`_StubApiClient`에 POST 기록과 실패 주입을 추가한다.

```dart
_StubApiClient(
  this.response, {
  this.error,
  this.postError,
  this.postResponse = const ApiResponse(statusCode: 204, jsonBody: null),
});

final Object? postError;
final ApiResponse postResponse;
final postPaths = <String>[];
final postBodies = <Map<String, Object?>>[];

@override
Future<ApiResponse> postJson(
  String path, {
  required Map<String, Object?> body,
  Map<String, String> headers = const {},
}) async {
  postPaths.add(path);
  postBodies.add(Map<String, Object?>.of(body));
  if (postError != null) {
    throw postError!;
  }
  return postResponse;
}
```

세 필드 payload와 204, 두 실패 종류를 검증한다.

```dart
test('event는 정확한 세 필드만 POST하고 204를 완료로 취급한다', () async {
  final client = _StubApiClient(_response(204));
  final repository = AdRepository(client);

  await repository.recordEvent(
    AdPlacement.routeResultBottom,
    'creative-1',
    AdEventType.impression,
  );

  expect(client.postPaths, ['/api/ads/events']);
  expect(client.postBodies, [
    {
      'placement': 'route-result-bottom',
      'creativeId': 'creative-1',
      'eventType': 'IMPRESSION',
    },
  ]);
});

test('event network와 timeout 실패는 저장이나 재시도 없이 무시한다', () async {
  for (final error in [
    const ApiException('network'),
    const ApiException('timeout'),
  ]) {
    final client = _StubApiClient(_response(204), postError: error);
    await expectLater(
      AdRepository(client).recordEvent(
        AdPlacement.routeResultBottom,
        'creative-1',
        AdEventType.click,
      ),
      completes,
    );
    expect(client.postBodies, hasLength(1));
  }
});
```

기존 `GET active 요청의 method, path, query가 정확하고 event 요청은 없다` test 이름은 `GET active 요청의 method, path, query가 정확하고 식별 header가 없다`로 바꾸고, `/api/ads/events`가 없다는 마지막 assertion만 제거한다. GET 자체의 두 요청, method, query, 식별 header 부재 assertions은 유지한다.

- [ ] **Step 6: repository focused test를 실행해 RED를 확인한다**

Run from `apps/mobile`: `flutter test test/features/ads/ad_repository_test.dart`

Expected: compile FAIL — `AdCreative`에 `endsAt` getter가 없고 `AdEventType` 및 `AdRepository.recordEvent`가 정의되지 않았다.

- [ ] **Step 7: UTC model parsing과 event POST를 최소 구현한다**

`ad_repository.dart`에 event enum과 model 필드를 추가한다.

```dart
enum AdEventType {
  impression('IMPRESSION'),
  click('CLICK');

  const AdEventType(this.wireValue);
  final String wireValue;
}
```

```dart
const AdCreative({
  required this.placement,
  required this.creativeId,
  required this.imageUrl,
  required this.landingUrl,
  required this.advertiserName,
  required this.altText,
  required this.endsAt,
});

final DateTime? endsAt;
```

`fetchActive`의 field parsing과 invalid guard에 다음 내용을 넣고 constructor로 전달한다.

```dart
final endsAtValue = data['endsAt'];
final endsAt = _utcDateTime(endsAtValue);
if (endsAtValue != null && endsAt == null) {
  return null;
}
```

```dart
return AdCreative(
  placement: placement,
  creativeId: creativeId,
  imageUrl: imageUrl,
  landingUrl: landingUrl,
  advertiserName: advertiserName,
  altText: altText,
  endsAt: endsAt,
);
```

```dart
DateTime? _utcDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.isUtc ? parsed : null;
}
```

`AdRepository` 안에 기존 lazy client 해소를 그대로 재사용하는 method를 추가한다. 응답 status는 UI 상태로 노출하지 않는다.

```dart
Future<void> recordEvent(
  AdPlacement placement,
  String creativeId,
  AdEventType eventType,
) async {
  final resolvedClient = _apiClient ?? _lazyClient();
  if (resolvedClient == null) {
    return;
  }
  try {
    final response = await resolvedClient.postJson(
      '/api/ads/events',
      body: {
        'placement': placement.id,
        'creativeId': creativeId,
        'eventType': eventType.wireValue,
      },
    );
    if (response.statusCode != 204) {
      return;
    }
  } on ApiException {
    return;
  }
}
```

- [ ] **Step 8: 두 mobile focused test를 실행해 GREEN을 확인한다**

Run from `apps/mobile`: `flutter test test/core/network/api_client_test.dart test/features/ads/ad_repository_test.dart`

Expected: PASS — 204는 null body로 성공하고, `endsAt`은 UTC/null만 허용하며, event는 정확한 세 필드로 한 번 POST되고 network/timeout이 UI로 전파되지 않는다.

- [ ] **Step 9: Task 2만 커밋한다**

```bash
git add apps/mobile/lib/core/network/api_client.dart apps/mobile/test/core/network/api_client_test.dart apps/mobile/lib/features/ads/ad_repository.dart apps/mobile/test/features/ads/ad_repository_test.dart
git commit -m "feat(ads): 무식별 이벤트 전송 계약 추가 (#1971)"
```

---

### Task 3: `ActiveAdBanner` impression/click/expiry lifecycle

**Files:**
- Modify: `apps/mobile/test/features/ads/active_ad_banner_test.dart:13-515`
- Modify: `apps/mobile/lib/features/ads/active_ad_banner.dart:31-105`

**Interfaces:**
- Consumes: Task 2의 `AdCreative.endsAt: DateTime?`, `AdRepository.recordEvent(AdPlacement, String, AdEventType): Future<void>`
- Produces: 현재 generation의 post-frame impression 1회, tap별 click fire-and-forget, `Timer? _expiryTimer` 기반 즉시 collapse와 lifecycle cancel

- [ ] **Step 1: widget test helper가 GET과 event POST를 함께 관찰하도록 확장한다**

`_StubApiClient`에 event response와 요청 기록을 추가한다.

```dart
_StubApiClient(
  this.response, {
  this.error,
  this.eventResponse,
  this.eventError,
}) : super(baseUri: Uri.parse('https://api.easysubway.example'));

final Future<ApiResponse>? eventResponse;
final Object? eventError;
final eventBodies = <Map<String, Object?>>[];
var getCalls = 0;

@override
Future<ApiResponse> getJson(
  String path, {
  Map<String, String> headers = const {},
}) async {
  getCalls++;
  if (error != null) {
    throw error!;
  }
  return response;
}

@override
Future<ApiResponse> postJson(
  String path, {
  required Map<String, Object?> body,
  Map<String, String> headers = const {},
}) async {
  eventBodies.add(Map<String, Object?>.of(body));
  if (eventError != null) {
    throw eventError!;
  }
  if (eventResponse != null) {
    return eventResponse!;
  }
  return const ApiResponse(statusCode: 204, jsonBody: null);
}
```

`_creativeResponse`가 Task 2의 contract에 맞춰 `endsAt`을 항상 포함하게 한다.

```dart
ApiResponse _creativeResponse({
  String placement = 'route-result-bottom',
  String imageUrl = 'https://cdn.easysubway.app/banner.png',
  String advertiserName = '이지상점',
  String altText = '여름 할인 배너',
  Object? endsAt = '2099-12-31T23:59:59Z',
}) => ApiResponse(
  statusCode: 200,
  jsonBody: <String, Object?>{
    'success': true,
    'data': <String, Object?>{
      'placement': placement,
      'creativeId': 'creative-1',
      'imageUrl': imageUrl,
      'landingUrl': 'https://advertiser.example/campaign',
      'advertiserName': advertiserName,
      'altText': altText,
      'endsAt': endsAt,
    },
  },
);
```

- [ ] **Step 2: render 전 없음과 render 뒤 생명주기당 impression 1회의 failing test를 작성한다**

```dart
testWidgets('impression은 decode와 실제 frame render 뒤 생명주기당 한 번 보낸다', (
  tester,
) async {
  final image = Completer<ImageProvider<Object>>();
  final client = _StubApiClient(Future.value(_creativeResponse()));
  await _pumpBanner(
    tester,
    repository: AdRepository(client),
    imageLoader: (_, _) => image.future,
  );
  await tester.pump();

  expect(find.byType(AdBannerSlot), findsNothing);
  expect(client.eventBodies, isEmpty);

  image.complete(_image);
  await tester.pump();
  await tester.pump();

  expect(find.byType(AdBannerSlot), findsOneWidget);
  expect(client.eventBodies, [
    {
      'placement': 'route-result-bottom',
      'creativeId': 'creative-1',
      'eventType': 'IMPRESSION',
    },
  ]);

  await tester.pump();
  expect(client.eventBodies, hasLength(1));
});
```

- [ ] **Step 3: tap별 click과 landing 독립성의 failing test를 작성한다**

```dart
testWidgets('tap마다 click을 fire-and-forget하고 event 대기와 무관하게 landing을 연다', (
  tester,
) async {
  final pendingEvent = Completer<ApiResponse>();
  final client = _StubApiClient(
    Future.value(_creativeResponse()),
    eventResponse: pendingEvent.future,
  );
  final launches = <Uri>[];
  await _pumpBanner(
    tester,
    repository: AdRepository(client),
    imageLoader: (_, _) async => _image,
    launcher: (uri, {required mode}) async {
      launches.add(uri);
      return true;
    },
  );
  await tester.pump();
  await tester.pump();

  final target = find.byKey(const Key('activeAdBannerTapTarget'));
  await tester.tap(target);
  await tester.tap(target);
  await tester.pump();

  expect(
    client.eventBodies.where((body) => body['eventType'] == 'CLICK'),
    hasLength(2),
  );
  expect(launches, [
    Uri.parse('https://advertiser.example/campaign'),
    Uri.parse('https://advertiser.example/campaign'),
  ]);

  pendingEvent.complete(
    const ApiResponse(statusCode: 204, jsonBody: null),
  );
});
```

event POST 자체가 실패해도 landing을 막지 않는 test도 추가한다.

```dart
testWidgets('click event 실패는 외부 browser landing을 막지 않는다', (tester) async {
  final client = _StubApiClient(
    Future.value(_creativeResponse()),
    eventError: const ApiException('offline'),
  );
  var launches = 0;
  await _pumpBanner(
    tester,
    repository: AdRepository(client),
    imageLoader: (_, _) async => _image,
    launcher: (uri, {required mode}) async {
      launches++;
      return true;
    },
  );
  await tester.pump();
  await tester.pump();

  await tester.tap(find.byKey(const Key('activeAdBannerTapTarget')));
  await tester.pump();

  expect(launches, 1);
  expect(
    client.eventBodies.where((body) => body['eventType'] == 'CLICK'),
    hasLength(1),
  );
  expect(tester.takeException(), isNull);
});
```

기존 `외부 브라우저 실패나 예외에 fallback을 만들지 않는다` test도 그대로 유지한다.

- [ ] **Step 4: 만료 전 숨김, 정시 collapse, refetch 없음의 failing tests를 작성한다**

```dart
testWidgets('이미 만료된 creative는 decode, render, impression을 모두 생략한다', (
  tester,
) async {
  final client = _StubApiClient(
    Future.value(
      _creativeResponse(
        endsAt: DateTime.now()
            .toUtc()
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      ),
    ),
  );
  var decodeCalls = 0;
  await _pumpBanner(
    tester,
    repository: AdRepository(client),
    imageLoader: (_, _) async {
      decodeCalls++;
      return _image;
    },
  );
  await tester.pump();

  expect(decodeCalls, 0);
  expect(find.byType(AdBannerSlot), findsNothing);
  expect(client.eventBodies, isEmpty);
});
```

```dart
testWidgets('미래 endsAt에 즉시 collapse하고 자동 refetch하지 않는다', (tester) async {
  final client = _StubApiClient(
    Future.value(
      _creativeResponse(
        endsAt: DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 5))
            .toIso8601String(),
      ),
    ),
  );
  await _pumpBanner(
    tester,
    repository: AdRepository(client),
    imageLoader: (_, _) async => _image,
  );
  await tester.pump();
  await tester.pump();
  expect(find.byType(AdBannerSlot), findsOneWidget);

  await tester.pump(const Duration(seconds: 5));

  expect(find.byType(AdBannerSlot), findsNothing);
  expect(client.getCalls, 1);
});
```

- [ ] **Step 5: widget 교체와 dispose가 이전 Timer lifecycle을 폐기하는 failing test를 작성한다**

```dart
testWidgets('widget 교체는 이전 expiry Timer를 cancel하고 dispose 뒤 callback을 남기지 않는다', (
  tester,
) async {
  const bannerKey = ValueKey('expiry-generation-banner');
  final firstClient = _StubApiClient(
    Future.value(
      _creativeResponse(
        advertiserName: '이전 광고',
        endsAt: DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 5))
            .toIso8601String(),
      ),
    ),
  );
  await _pumpBanner(
    tester,
    bannerKey: bannerKey,
    repository: AdRepository(firstClient),
    imageLoader: (_, _) async => _image,
  );
  await tester.pump();
  await tester.pump();

  final replacementClient = _StubApiClient(
    Future.value(
      _creativeResponse(
        advertiserName: '현재 광고',
        endsAt: DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      ),
    ),
  );
  await _pumpBanner(
    tester,
    bannerKey: bannerKey,
    repository: AdRepository(replacementClient),
    imageLoader: (_, _) async => _image,
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 5));

  expect(find.text('현재 광고'), findsOneWidget);
  expect(find.text('이전 광고'), findsNothing);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(hours: 1));
  expect(tester.takeException(), isNull);
});
```

기존 dependency 교체 parameterized test도 그대로 유지하여 repository, placement, imageLoader 각각의 reload가 이전 배너를 즉시 지우는 회귀 계약을 보존한다.

- [ ] **Step 6: widget focused test를 실행해 RED를 확인한다**

Run from `apps/mobile`: `flutter test test/features/ads/active_ad_banner_test.dart`

Expected: FAIL — event body가 비어 impression/click assertions이 실패하고, 만료 Timer가 없어 5초 뒤에도 `AdBannerSlot`이 남는다.

- [ ] **Step 7: generation별 Timer와 post-frame impression 상태를 최소 추가한다**

state에 두 필드를 추가한다.

```dart
Timer? _expiryTimer;
bool _impressionRecorded = false;
```

reload 시작과 dispose에서 현재 lifecycle을 폐기한다.

```dart
void _resetLifecycle() {
  _expiryTimer?.cancel();
  _expiryTimer = null;
  _impressionRecorded = false;
}

void _reload() {
  _resetLifecycle();
  final generation = ++_generation;
  unawaited(
    _load(
      generation,
      widget.repository,
      widget.placement,
      widget.imageLoader,
    ),
  );
}

@override
void dispose() {
  _generation++;
  _resetLifecycle();
  super.dispose();
}
```

`_load`에서 fetch 직후와 decode 직후 모두 만료를 확인하고, render state 뒤 현재 generation Timer 하나와 post-frame callback을 예약한다.

```dart
final creative = await repository.fetchActive(placement);
if (!mounted || generation != _generation || creative == null) {
  return;
}
if (_isExpired(creative)) {
  return;
}
final image = await imageLoader(creative.imageUrl, context);
if (!mounted || generation != _generation || _isExpired(creative)) {
  return;
}
setState(() {
  _creative = creative;
  _image = image;
});
_scheduleExpiry(generation, creative);
_recordImpressionAfterFrame(generation, repository, creative);
```

```dart
bool _isExpired(AdCreative creative) {
  final endsAt = creative.endsAt;
  return endsAt != null && !endsAt.isAfter(DateTime.now().toUtc());
}

void _scheduleExpiry(int generation, AdCreative creative) {
  final endsAt = creative.endsAt;
  if (endsAt == null) {
    return;
  }
  _expiryTimer = Timer(endsAt.difference(DateTime.now().toUtc()), () {
    if (!mounted || generation != _generation || !identical(_creative, creative)) {
      return;
    }
    setState(() {
      _creative = null;
      _image = null;
    });
    _expiryTimer = null;
  });
}

void _recordImpressionAfterFrame(
  int generation,
  AdRepository repository,
  AdCreative creative,
) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted ||
        generation != _generation ||
        !identical(_creative, creative) ||
        _image == null ||
        _impressionRecorded) {
      return;
    }
    _impressionRecorded = true;
    unawaited(
      repository.recordEvent(
        creative.placement,
        creative.creativeId,
        AdEventType.impression,
      ),
    );
  });
}
```

- [ ] **Step 8: tap마다 click을 먼저 fire-and-forget하고 기존 landing을 계속 연다**

`_openLanding`은 현재 creative를 snapshot으로 잡고 event Future를 기다리지 않는다.

```dart
Future<void> _openLanding() async {
  final creative = _creative;
  if (creative == null) {
    return;
  }
  unawaited(
    widget.repository.recordEvent(
      creative.placement,
      creative.creativeId,
      AdEventType.click,
    ),
  );
  try {
    await widget.launcher(
      creative.landingUrl,
      mode: LaunchMode.externalApplication,
    );
  } on Exception {
    // 외부 브라우저 실패 시 내부 이동이나 다른 URL로 fallback하지 않는다.
  }
}
```

- [ ] **Step 9: widget focused test를 실행해 GREEN을 확인한다**

Run from `apps/mobile`: `flutter test test/features/ads/active_ad_banner_test.dart`

Expected: PASS — 실제 render 뒤 impression 1회, tap별 click, event 실패와 독립적인 external landing, 만료 collapse, refetch 없음, replacement/dispose Timer 폐기가 모두 통과한다.

- [ ] **Step 10: Task 3만 커밋한다**

```bash
git add apps/mobile/lib/features/ads/active_ad_banner.dart apps/mobile/test/features/ads/active_ad_banner_test.dart
git commit -m "feat(ads): 배너 이벤트와 만료 lifecycle 적용 (#1971)"
```

---

### Task 4: Privacy/store/repository 계약과 최종 검증

**Files:**
- Modify: `apps/mobile/release/store-privacy-inventory.json:5-15`
- Modify: `apps/mobile/release/store-submission-readiness.json:100-109`
- Modify: `tools/ci/repository-contract.test.mjs:2783-2962`

**Interfaces:**
- Consumes: Task 2의 유일한 Dart sender `apps/mobile/lib/features/ads/ad_repository.dart`와 Task 3의 render/click/expiry focused test evidence
- Produces: `advertising.measurementEvents: true`; event sender allowlist 1개; `collectedDataTypeIds: []`, SDK/`AD_ID`/tracking 금지; production E2E owner-deferred store readiness 기록

- [ ] **Step 1: 새 개인정보·sender 경계를 요구하는 repository contract RED를 작성한다**

기존 test 이름을 `자체 서빙 광고 store 계약은 무추적·무식별 계측 경계를 함께 고정한다`로 바꾸고 measurement assertion을 분리한다.

```js
for (const field of ["personalized", "adId", "thirdPartyAdSdk", "tracking"]) {
  assert.equal(privacyInventory.advertising[field], false, `advertising.${field} must remain false`);
}
assert.equal(privacyInventory.advertising.measurementEvents, true);
assert.deepEqual(privacyInventory.advertising.collectedDataTypeIds, []);
```

모든 production Dart에서 endpoint를 금지하던 loop는 유일 sender allowlist와 exact repository test evidence로 교체한다.

```js
const adEventSenders = mobileProductionDartFiles()
  .filter((sourcePath) => /\/api\/ads\/events/.test(read(sourcePath)));
assert.deepEqual(adEventSenders, [
  "apps/mobile/lib/features/ads/ad_repository.dart",
]);

const adRepository = read("apps/mobile/lib/features/ads/ad_repository.dart");
assert.match(adRepository, /Future<void> recordEvent\(/);
assert.match(adRepository, /postJson\(\s*'\/api\/ads\/events'/);
assert.match(adRepository, /'placement': placement\.id/);
assert.match(adRepository, /'creativeId': creativeId/);
assert.match(adRepository, /'eventType': eventType\.wireValue/);
```

기존 `자체 서빙 광고 native 경계는 SDK·AD_ID·event POST를 release 산출물까지 차단한다` test는 native sender 금지로 그대로 둔다. 끝부분의 오래된 GET-only test source assertions는 다음 계약으로 교체한다.

```js
const adRepositoryTest = read("apps/mobile/test/features/ads/ad_repository_test.dart");
assert.match(adRepositoryTest, /test\('event는 정확한 세 필드만 POST하고 204를 완료로 취급한다'/);
assert.match(adRepositoryTest, /'placement': 'route-result-bottom'/);
assert.match(adRepositoryTest, /'creativeId': 'creative-1'/);
assert.match(adRepositoryTest, /'eventType': 'IMPRESSION'/);
assert.match(adRepositoryTest, /network와 timeout 실패는 저장이나 재시도 없이 무시한다/);

const bannerTest = read("apps/mobile/test/features/ads/active_ad_banner_test.dart");
assert.match(bannerTest, /실제 frame render 뒤 생명주기당 한 번/);
assert.match(bannerTest, /tap마다 click을 fire-and-forget/);
assert.match(bannerTest, /미래 endsAt에 즉시 collapse하고 자동 refetch하지 않는다/);
```

- [ ] **Step 2: repository contract focused test를 실행해 RED를 확인한다**

Run: `node --test --test-name-pattern "자체 서빙 광고 store 계약|자체 서빙 광고 native 경계" tools/ci/repository-contract.test.mjs`

Expected: FAIL — `store-privacy-inventory.json`의 `advertising.measurementEvents`가 아직 false이고 store readiness가 아직 event 계측 없음으로 선언되어 새 계약과 불일치한다.

- [ ] **Step 3: 개인정보 inventory를 무식별 measurement 사용 사실로만 갱신한다**

`store-privacy-inventory.json`의 advertising block은 다음 값을 갖게 한다. 다른 `dataTypes`, top-level `tracking`, 공유·삭제 계약은 변경하지 않는다.

```json
"advertising": {
  "included": true,
  "servingModel": "first-party-self-served",
  "personalized": false,
  "adId": false,
  "thirdPartyAdSdk": false,
  "tracking": false,
  "measurementEvents": true,
  "collectedDataTypeIds": [],
  "lastVerifiedAt": "2026-07-12"
}
```

- [ ] **Step 4: store readiness에 code evidence와 production E2E owner-deferred 경계를 기록한다**

`play_ads_declaration` item을 다음 내용으로 갱신한다.

```json
{
  "id": "play_ads_declaration",
  "store": "google-play",
  "category": "app-content",
  "titleKo": "Play 광고 포함 여부",
  "decisionOwnerKo": "제품/사업 담당",
  "readyWhenKo": "자체 서빙 비개인화 하우스/제휴 배너를 포함하므로 Play Console 광고 포함 여부를 예로 제출한다. impression/click은 사용자·기기·세션 식별자 없이 일별 count로만 집계하고 AD_ID, 제3자 광고 SDK, 개인화, tracking은 사용하지 않는다. code release에서는 API·widget·privacy contract를 증거로 사용하며, production 소재·event 집계 E2E는 owner 승인으로 deferred하고 Play Store 게시 후 impression 1회, click, 종료 collapse, 일별 count를 확인한다.",
  "evidence": ["dependency-review", "business-model-review", "ad-request-contract-test", "ad-event-expiry-contract-test", "post-publish-ad-event-expiry-e2e-owner-deferred"],
  "linkedArtifacts": ["apps/mobile/lib/features/ads/ad_repository.dart", "apps/mobile/lib/features/ads/active_ad_banner.dart", "apps/mobile/release/store-privacy-inventory.json"],
  "configurationSources": ["first-party self-served in-app ad placement", "anonymous impression and click daily count", "no third-party ad SDK dependency", "no AD_ID permission", "no personalized ads or tracking"]
}
```

repository contract에 아래 assertions도 추가해 이 deferred 문구가 빈 약속으로 사라지지 않게 한다.

```js
assert.match(adDisclosure.readyWhenKo, /사용자·기기·세션 식별자 없이 일별 count/);
assert.match(adDisclosure.readyWhenKo, /production 소재·event 집계 E2E는 owner 승인으로 deferred/);
assert.match(adDisclosure.readyWhenKo, /Play Store 게시 후 impression 1회, click, 종료 collapse, 일별 count/);
assert.ok(adDisclosure.evidence.includes("ad-event-expiry-contract-test"));
assert.ok(adDisclosure.evidence.includes("post-publish-ad-event-expiry-e2e-owner-deferred"));
```

- [ ] **Step 5: repository contract focused test를 다시 실행해 GREEN을 확인한다**

Run: `node --test --test-name-pattern "자체 서빙 광고 store 계약|자체 서빙 광고 native 경계|모바일 스토어 개인정보 인벤토리" tools/ci/repository-contract.test.mjs`

Expected: PASS — Dart sender는 `AdRepository` 하나뿐이고, native event sender·광고 SDK·`AD_ID`·tracking은 금지되며, measurement event 사용과 owner-deferred production E2E가 계약에 남는다.

- [ ] **Step 6: issue #1971 전체 focused verification을 실행한다**

Run: `backend/gradlew test --tests com.easysubway.ads.adapter.in.web.AdPublicControllerTest`

Expected: PASS

Run from `apps/mobile`: `flutter test test/core/network/api_client_test.dart test/features/ads/ad_repository_test.dart test/features/ads/active_ad_banner_test.dart`

Expected: PASS

Run: `node --test --test-name-pattern "자체 서빙 광고 store 계약|자체 서빙 광고 native 경계|모바일 스토어 개인정보 인벤토리" tools/ci/repository-contract.test.mjs`

Expected: PASS

Run: `git diff --check`

Expected: exit 0 with no output. `README.md`, dependency manifests, Android/iOS native manifests, DB migrations에는 diff가 없어야 한다.

- [ ] **Step 7: Task 4만 커밋한다**

```bash
git add apps/mobile/release/store-privacy-inventory.json apps/mobile/release/store-submission-readiness.json tools/ci/repository-contract.test.mjs
git commit -m "test(ads): 무식별 계측 개인정보 계약 고정 (#1971)"
```
