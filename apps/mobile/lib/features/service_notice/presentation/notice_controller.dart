import 'package:flutter/foundation.dart';

import '../data/notice_repository.dart';
import '../domain/service_notice.dart';
import 'notice_time_label.dart';

/// 운행 공지의 앱 시작·포그라운드 복귀 조회 상태를 들고, 노선도 홈 배너와
/// "운행 공지" 목록 화면이 함께 구독하는 컨트롤러.
///
/// 별도 폴링 주기를 신설하지 않는다 — [refresh]는 앱 시작과 포그라운드 복귀
/// 트리거에서만 호출된다. 배너 닫기는 세션 동안만 유지한다(다음 조회에서 여전히
/// 활성이면 목록에는 남지만 배너는 사용자가 닫은 채로 둔다).
class NoticeController extends ChangeNotifier {
  NoticeController({required this.repository});

  final NoticeRepository repository;

  ActiveNoticesResult? _result;
  bool _loading = false;
  bool _disposed = false;
  Future<void>? _inFlight;
  final Set<String> _dismissedBannerIds = <String>{};

  ActiveNoticesResult? get result => _result;

  bool get loading => _loading;

  List<ServiceNotice> get notices => _result?.notices ?? const [];

  bool get isStale => _result?.stale ?? false;

  DateTime? get asOf => _result?.asOf;

  /// 오프라인 강등 시 마지막 수신 시각 라벨("N시간 전 기준"). 배너·목록이 공유하는
  /// 단일 출처(신선하면 null).
  String? staleLabel(DateTime now) {
    final at = asOf;
    if (!isStale || at == null) {
      return null;
    }
    return formatNoticeAsOf(at, now);
  }

  /// 배너로 승격할 첫 disruption. 이미 닫은 공지는 제외한다.
  ServiceNotice? get topDisruption {
    for (final notice in notices) {
      if (notice.isDisruption && !_dismissedBannerIds.contains(notice.id)) {
        return notice;
      }
    }
    return null;
  }

  /// 활성 공지를 다시 조회한다. 이미 진행 중이면 그 호출에 합류한다.
  Future<void> refresh() {
    return _inFlight ??= _run();
  }

  Future<void> _run() async {
    _loading = true;
    _safeNotify();
    try {
      final result = await repository.activeNotices();
      _result = result;
    } catch (error, stackTrace) {
      // 조회 실패는 조용히 이전 상태를 유지한다(repository가 이미 stale 강등을
      // 담당하므로 여기까지 오는 예외는 표시할 사용자 메시지가 없다).
      debugPrint('운행 공지 조회 실패: $error\n$stackTrace');
    } finally {
      _loading = false;
      _inFlight = null;
      // 조회가 in-flight인 동안 소유 State가 dispose되면 컨트롤러가 먼저 dispose되므로,
      // 완료 후 통지는 dispose 이후 사용(FlutterError)을 피하려 가드한다.
      _safeNotify();
    }
  }

  void dismissBanner(String id) {
    if (_dismissedBannerIds.add(id)) {
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
