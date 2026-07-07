import 'dart:async';

import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:easysubway_mobile/features/service_notice/presentation/notice_controller.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceNotice notice(
  String id, {
  NoticeSeverity severity = NoticeSeverity.disruption,
}) {
  return ServiceNotice(
    id: id,
    scope: NoticeScope.all,
    title: '제목 $id',
    body: '본문 $id',
    severity: severity,
    publishedAt: DateTime(2026, 7, 6, 9, 0, 0),
  );
}

class _FakeRepository implements NoticeRepository {
  _FakeRepository(this._results);
  final List<ActiveNoticesResult> _results;
  int calls = 0;

  @override
  Future<ActiveNoticesResult> activeNotices() async {
    final result = _results[calls.clamp(0, _results.length - 1)];
    calls++;
    return result;
  }
}

class _ThrowingRepository implements NoticeRepository {
  @override
  Future<ActiveNoticesResult> activeNotices() async {
    throw StateError('boom');
  }
}

class _DeferredRepository implements NoticeRepository {
  _DeferredRepository(this._future);
  final Future<ActiveNoticesResult> _future;
  int calls = 0;

  @override
  Future<ActiveNoticesResult> activeNotices() {
    calls++;
    return _future;
  }
}

void main() {
  test('refresh는 결과를 반영하고 리스너에 통지한다', () async {
    final repo = _FakeRepository([
      ActiveNoticesResult(notices: [notice('n1')], stale: false),
    ]);
    final controller = NoticeController(repository: repo);
    var notified = 0;
    controller.addListener(() => notified++);

    await controller.refresh();

    expect(controller.notices, hasLength(1));
    expect(controller.isStale, isFalse);
    expect(notified, greaterThan(0));
  });

  test('topDisruption은 disruption만 승격하고 info는 배너에서 제외', () async {
    final repo = _FakeRepository([
      ActiveNoticesResult(
        notices: [
          notice('info1', severity: NoticeSeverity.info),
          notice('dis1'),
        ],
        stale: false,
      ),
    ]);
    final controller = NoticeController(repository: repo);

    await controller.refresh();

    expect(controller.topDisruption?.id, 'dis1');
  });

  test('배너를 닫으면 해당 공지는 topDisruption에서 빠진다', () async {
    final repo = _FakeRepository([
      ActiveNoticesResult(
        notices: [notice('dis1'), notice('dis2')],
        stale: false,
      ),
    ]);
    final controller = NoticeController(repository: repo);
    await controller.refresh();

    controller.dismissBanner('dis1');

    expect(controller.topDisruption?.id, 'dis2');
  });

  test('모든 disruption을 닫으면 topDisruption은 null', () async {
    final repo = _FakeRepository([
      ActiveNoticesResult(notices: [notice('dis1')], stale: false),
    ]);
    final controller = NoticeController(repository: repo);
    await controller.refresh();

    controller.dismissBanner('dis1');

    expect(controller.topDisruption, isNull);
  });

  test('저장소가 예외를 던져도 이전 상태를 유지하고 삼킨다', () async {
    final controller = NoticeController(repository: _ThrowingRepository());

    await controller.refresh();

    expect(controller.notices, isEmpty);
    expect(controller.loading, isFalse);
  });

  test('진행 중 refresh가 있으면 중복 호출은 합류(single-flight)', () async {
    final repo = _FakeRepository([
      ActiveNoticesResult(notices: [notice('n1')], stale: false),
    ]);
    final controller = NoticeController(repository: repo);

    await Future.wait([controller.refresh(), controller.refresh()]);

    expect(repo.calls, 1);
  });

  test('dispose 후 in-flight refresh가 완료돼도 통지하지 않는다', () async {
    final completer = Completer<ActiveNoticesResult>();
    final controller = NoticeController(
      repository: _DeferredRepository(completer.future),
    );
    var notifiedAfterDispose = false;

    final pending = controller.refresh();
    controller.addListener(() => notifiedAfterDispose = true);
    controller.dispose();
    completer.complete(const ActiveNoticesResult(notices: [], stale: false));

    // dispose된 ChangeNotifier에 통지하면 FlutterError를 던진다 — 던지지 않아야 한다.
    await expectLater(pending, completes);
    expect(notifiedAfterDispose, isFalse);
  });

  test('staleLabel은 stale일 때만 라벨을 낸다', () async {
    final now = DateTime(2026, 7, 6, 12, 0, 0);
    final fresh = _FakeRepository([
      ActiveNoticesResult(notices: [notice('n1')], stale: false),
    ]);
    final freshController = NoticeController(repository: fresh);
    await freshController.refresh();
    expect(freshController.staleLabel(now), isNull);

    final stale = _FakeRepository([
      ActiveNoticesResult(
        notices: [notice('n1')],
        stale: true,
        asOf: DateTime(2026, 7, 6, 9, 0, 0),
      ),
    ]);
    final staleController = NoticeController(repository: stale);
    await staleController.refresh();
    expect(staleController.staleLabel(now), '3시간 전 기준');
  });
}
