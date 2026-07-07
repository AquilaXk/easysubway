import '../../../core/network/api_client.dart';
import '../domain/service_notice.dart';

/// 활성 공지 조회 결과. [stale]이면 오프라인/오류로 마지막 수신본을 준 것이고,
/// [asOf]는 그 데이터의 수신 시각("N시간 전 기준" 라벨용)이다.
class ActiveNoticesResult {
  const ActiveNoticesResult({
    required this.notices,
    required this.stale,
    this.asOf,
  });

  final List<ServiceNotice> notices;
  final bool stale;
  final DateTime? asOf;

  List<ServiceNotice> get disruptions =>
      notices.where((notice) => notice.isDisruption).toList();
}

/// 공개 공지 API의 좁은 포트. If-None-Match 조건부 GET만 노출한다.
abstract class NoticeApiClient {
  Future<ApiResponse> getActiveNotices({String? ifNoneMatch});
}

/// [ApiClient]로 `GET /api/notices/active`를 호출하는 구현.
class HttpNoticeApiClient implements NoticeApiClient {
  HttpNoticeApiClient(this._apiClient);

  final ApiClient _apiClient;

  @override
  Future<ApiResponse> getActiveNotices({String? ifNoneMatch}) {
    return _apiClient.getJson(
      '/api/notices/active',
      headers: ifNoneMatch == null ? const {} : {'If-None-Match': ifNoneMatch},
    );
  }
}

/// 공지 캐시 항목(etag·공지 목록·수신 시각).
class NoticeCacheEntry {
  const NoticeCacheEntry({
    required this.etag,
    required this.notices,
    required this.fetchedAt,
  });

  final String? etag;
  final List<ServiceNotice> notices;
  final DateTime fetchedAt;
}

/// 공지 캐시 저장소(앱 재시작 후 오프라인 staleness용).
abstract class NoticeCacheStore {
  Future<NoticeCacheEntry?> load();

  Future<void> save(NoticeCacheEntry entry);
}

/// 활성 공지를 조회한다.
abstract class NoticeRepository {
  Future<ActiveNoticesResult> activeNotices();
}

/// ETag 조건부 GET + 캐시 + 오프라인 강등을 수행하는 구현.
class ApiNoticeRepository implements NoticeRepository {
  ApiNoticeRepository({
    required this.apiClient,
    required this.cacheStore,
    this.now = DateTime.now,
  });

  final NoticeApiClient apiClient;
  final NoticeCacheStore cacheStore;
  final DateTime Function() now;

  @override
  Future<ActiveNoticesResult> activeNotices() async {
    final cached = await cacheStore.load();
    try {
      final response = await apiClient.getActiveNotices(
        ifNoneMatch: cached?.etag,
      );

      if (response.isNotModified && cached != null) {
        final fetchedAt = now();
        await cacheStore.save(
          NoticeCacheEntry(
            etag: cached.etag,
            notices: cached.notices,
            fetchedAt: fetchedAt,
          ),
        );
        return ActiveNoticesResult(
          notices: cached.notices,
          stale: false,
          asOf: fetchedAt,
        );
      }

      if (response.isOk && response.jsonBody is Map<String, Object?>) {
        final data = (response.jsonBody as Map<String, Object?>)['data'];
        final notices = ServiceNotice.listFromApiData(data);
        final fetchedAt = now();
        await cacheStore.save(
          NoticeCacheEntry(
            etag: response.etag,
            notices: notices,
            fetchedAt: fetchedAt,
          ),
        );
        return ActiveNoticesResult(
          notices: notices,
          stale: false,
          asOf: fetchedAt,
        );
      }
    } on ApiException {
      // 오프라인/서버 오류 → 아래에서 캐시로 강등.
    }

    if (cached != null) {
      return ActiveNoticesResult(
        notices: cached.notices,
        stale: true,
        asOf: cached.fetchedAt,
      );
    }
    return const ActiveNoticesResult(notices: [], stale: false);
  }
}
