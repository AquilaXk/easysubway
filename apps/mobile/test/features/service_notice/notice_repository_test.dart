import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
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
  NoticeCacheEntry? entry;
  @override
  Future<NoticeCacheEntry?> load() async => entry;
  @override
  Future<void> save(NoticeCacheEntry e) async => entry = e;
}

ApiResponse okResponse(List<Map<String, Object?>> data, {String? etag}) {
  return ApiResponse(
    statusCode: 200,
    jsonBody: {'success': true, 'data': data, 'message': null},
    etag: etag,
  );
}

Map<String, Object?> noticeJson(String id, String severity) => {
  'id': id,
  'scope': 'ALL',
  'scopeValue': null,
  'title': '제목 $id',
  'body': '본문',
  'severity': severity,
  'publishedAt': '2026-07-06T09:00:00',
  'expiresAt': null,
};

void main() {
  final now = DateTime(2026, 7, 6, 12, 0, 0);

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
}
