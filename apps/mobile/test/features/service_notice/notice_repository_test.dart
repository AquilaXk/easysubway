import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApiClient implements NoticeApiClient {
  _FakeApiClient(this.response, {this.throwError = false});
  ApiResponse response;
  bool throwError;
  String? lastIfNoneMatch;
  int calls = 0;

  @override
  Future<ApiResponse> getActiveNotices({String? ifNoneMatch}) async {
    calls++;
    lastIfNoneMatch = ifNoneMatch;
    if (throwError) {
      throw const ApiException('offline');
    }
    return response;
  }
}

class _InMemoryCache implements NoticeCacheStore {
  _InMemoryCache({this.loadError, this.saveError});

  NoticeCacheEntry? entry;
  final Object? loadError;
  final Object? saveError;

  @override
  Future<NoticeCacheEntry?> load() async {
    if (loadError != null) {
      throw loadError!;
    }
    return entry;
  }

  @override
  Future<void> save(NoticeCacheEntry e) async {
    if (saveError != null) {
      throw saveError!;
    }
    entry = e;
  }
}

ApiResponse okResponse(List<Map<String, Object?>> data, {String? etag}) {
  return ApiResponse(
    statusCode: 200,
    jsonBody: {'success': true, 'data': data, 'message': null},
    etag: etag,
  );
}

Map<String, Object?> noticeJson(
  String id,
  String severity, {
  String publishedAt = '2026-07-06T09:00:00',
  String? expiresAt,
}) => {
  'id': id,
  'scope': 'ALL',
  'scopeValue': null,
  'title': '제목 $id',
  'body': '본문',
  'severity': severity,
  'publishedAt': publishedAt,
  'expiresAt': expiresAt,
};

ServiceNotice notice(
  String id, {
  String publishedAt = '2026-07-06T09:00:00',
  String? expiresAt,
}) => ServiceNotice.fromJson(
  noticeJson(id, 'DISRUPTION', publishedAt: publishedAt, expiresAt: expiresAt),
)!;

void main() {
  final now = DateTime.utc(2026, 7, 6, 12, 0, 0);

  ApiNoticeRepository repo(_FakeApiClient client, _InMemoryCache cache) =>
      ApiNoticeRepository(apiClient: client, cacheStore: cache, now: () => now);

  test('200 응답은 공지를 파싱·캐시하고 fresh로 돌려준다', () async {
    final client = _FakeApiClient(
      okResponse([noticeJson('n1', 'DISRUPTION')], etag: '"e1"'),
    );
    final cache = _InMemoryCache();

    final result = await repo(client, cache).activeNotices();

    expect(result.notices, hasLength(1));
    expect(result.stale, isFalse);
    expect(result.asOf, now);
    expect(cache.entry!.etag, '"e1"');
    expect(cache.entry!.notices.single.id, 'n1');
  });

  test('캐시에 etag가 있으면 If-None-Match로 조건부 요청한다', () async {
    final cache = _InMemoryCache()
      ..entry = NoticeCacheEntry(
        etag: '"e1"',
        notices: [ServiceNotice.fromJson(noticeJson('n1', 'INFO'))!],
        fetchedAt: now.subtract(const Duration(minutes: 1)),
      );
    final client = _FakeApiClient(
      ApiResponse(statusCode: 304, jsonBody: null, etag: '"e1"'),
    );

    final result = await repo(client, cache).activeNotices();

    expect(client.lastIfNoneMatch, '"e1"');
    expect(result.notices.single.id, 'n1');
    expect(result.stale, isFalse);
  });

  test('오프라인(예외)이면 마지막 수신본을 stale로 돌려주고 asOf는 수신 시각', () async {
    final fetchedAt = now.subtract(const Duration(hours: 3));
    final cache = _InMemoryCache()
      ..entry = NoticeCacheEntry(
        etag: '"e1"',
        notices: [ServiceNotice.fromJson(noticeJson('n1', 'DISRUPTION'))!],
        fetchedAt: fetchedAt,
      );
    final client = _FakeApiClient(okResponse(const []), throwError: true);

    final result = await repo(client, cache).activeNotices();

    expect(result.notices, hasLength(1));
    expect(result.stale, isTrue);
    expect(result.asOf, fetchedAt);
  });

  test('오프라인이고 캐시도 없으면 빈 목록(비-stale)', () async {
    final client = _FakeApiClient(okResponse(const []), throwError: true);
    final result = await repo(client, _InMemoryCache()).activeNotices();

    expect(result.notices, isEmpty);
    expect(result.stale, isFalse);
  });

  test('캐시 읽기 실패는 보고하고 조건 없는 네트워크 응답을 사용한다', () async {
    final errors = <Object>[];
    final client = _FakeApiClient(
      okResponse([noticeJson('n1', 'DISRUPTION')], etag: '"e2"'),
    );
    final cache = _InMemoryCache(loadError: StateError('cache read failed'));

    final result = await runWithMobileErrorReporter(
      errors.add,
      () => repo(client, cache).activeNotices(),
    );

    expect(result.notices.single.id, 'n1');
    expect(result.stale, isFalse);
    expect(client.lastIfNoneMatch, isNull);
    expect(errors, hasLength(1));
  });

  test('200 응답 캐시 저장 실패는 보고하되 fresh 응답을 유지한다', () async {
    final errors = <Object>[];
    final client = _FakeApiClient(
      okResponse([noticeJson('n1', 'DISRUPTION')], etag: '"e1"'),
    );
    final cache = _InMemoryCache(saveError: StateError('cache save failed'));

    final result = await runWithMobileErrorReporter(
      errors.add,
      () => repo(client, cache).activeNotices(),
    );

    expect(result.notices.single.id, 'n1');
    expect(result.stale, isFalse);
    expect(result.asOf, now);
    expect(errors, hasLength(1));
  });

  test('304 응답 캐시 저장 실패도 검증된 캐시를 fresh로 유지한다', () async {
    final errors = <Object>[];
    final cache = _InMemoryCache(saveError: StateError('cache save failed'))
      ..entry = NoticeCacheEntry(
        etag: '"e1"',
        notices: [notice('n1')],
        fetchedAt: now.subtract(const Duration(hours: 1)),
      );
    final client = _FakeApiClient(
      ApiResponse(statusCode: 304, jsonBody: null, etag: '"e1"'),
    );

    final result = await runWithMobileErrorReporter(
      errors.add,
      () => repo(client, cache).activeNotices(),
    );

    expect(result.notices.single.id, 'n1');
    expect(result.stale, isFalse);
    expect(result.asOf, now);
    expect(errors, hasLength(1));
  });

  test('오프라인 캐시는 만료 공지와 미래 게시 공지를 노출하지 않는다', () async {
    final fetchedAt = now.subtract(const Duration(hours: 3));
    final cache = _InMemoryCache()
      ..entry = NoticeCacheEntry(
        etag: '"e1"',
        notices: [
          notice('active', expiresAt: '2026-07-06T12:01:00'),
          notice('expired', expiresAt: '2026-07-06T12:00:00'),
          notice('future', publishedAt: '2026-07-06T12:01:00'),
        ],
        fetchedAt: fetchedAt,
      );
    final client = _FakeApiClient(okResponse(const []), throwError: true);

    final result = await repo(client, cache).activeNotices();

    expect(result.notices.map((entry) => entry.id), ['active']);
    expect(result.stale, isTrue);
    expect(result.asOf, fetchedAt);
  });

  test('304 검증 캐시도 현재 시각 기준 활성 공지만 돌려준다', () async {
    final cache = _InMemoryCache()
      ..entry = NoticeCacheEntry(
        etag: '"e1"',
        notices: [
          notice('active'),
          notice('expired', expiresAt: '2026-07-06T11:59:59'),
          notice('future', publishedAt: '2026-07-06T12:00:01'),
        ],
        fetchedAt: now.subtract(const Duration(hours: 1)),
      );
    final client = _FakeApiClient(
      ApiResponse(statusCode: 304, jsonBody: null, etag: '"e1"'),
    );

    final result = await repo(client, cache).activeNotices();

    expect(result.notices.map((entry) => entry.id), ['active']);
    expect(cache.entry!.notices.map((entry) => entry.id), ['active']);
  });

  test('200 응답도 현재 시각 기준 활성 공지만 결과와 캐시에 저장한다', () async {
    final client = _FakeApiClient(
      okResponse([
        noticeJson('active', 'DISRUPTION', expiresAt: '2026-07-06T12:01:00'),
        noticeJson('expired', 'DISRUPTION', expiresAt: '2026-07-06T12:00:00'),
        noticeJson('future', 'DISRUPTION', publishedAt: '2026-07-06T12:01:00'),
      ]),
    );
    final cache = _InMemoryCache();

    final result = await repo(client, cache).activeNotices();

    expect(result.notices.map((entry) => entry.id), ['active']);
    expect(cache.entry!.notices.map((entry) => entry.id), ['active']);
  });
}
