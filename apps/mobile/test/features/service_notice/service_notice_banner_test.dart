import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:easysubway_mobile/features/service_notice/presentation/notice_controller.dart';
import 'package:easysubway_mobile/features/service_notice/presentation/service_notice_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceNotice _notice(
  String id, {
  NoticeSeverity severity = NoticeSeverity.disruption,
  String? title,
}) {
  return ServiceNotice(
    id: id,
    scope: NoticeScope.all,
    title: title ?? '제목 $id',
    body: '본문 $id',
    severity: severity,
    publishedAt: DateTime(2026, 7, 6, 9, 0, 0),
  );
}

class _FakeRepository implements NoticeRepository {
  _FakeRepository(this.result);
  final ActiveNoticesResult result;
  @override
  Future<ActiveNoticesResult> activeNotices() async => result;
}

Future<NoticeController> _seed(
  WidgetTester tester,
  ActiveNoticesResult result,
) async {
  final controller = NoticeController(repository: _FakeRepository(result));
  await controller.refresh();
  return controller;
}

Widget _host(NoticeController controller, {VoidCallback? onTap}) {
  return MaterialApp(
    home: Scaffold(
      body: ServiceNoticeBanner(
        controller: controller,
        onOpenList: onTap ?? () {},
        now: () => DateTime(2026, 7, 6, 12, 0, 0),
      ),
    ),
  );
}

void main() {
  testWidgets('disruption 공지가 있으면 제목을 1줄로 노출한다', (tester) async {
    final controller = await _seed(
      tester,
      ActiveNoticesResult(
        notices: [_notice('n1', title: '2호선 강남–역삼 지연 — 우회 경로를 확인하세요')],
        stale: false,
      ),
    );

    await tester.pumpWidget(_host(controller));

    expect(find.byKey(const Key('serviceNoticeBanner')), findsOneWidget);
    expect(find.text('2호선 강남–역삼 지연 — 우회 경로를 확인하세요'), findsOneWidget);
  });

  testWidgets('disruption이 없으면 아무것도 그리지 않는다', (tester) async {
    final controller = await _seed(
      tester,
      ActiveNoticesResult(
        notices: [_notice('i1', severity: NoticeSeverity.info)],
        stale: false,
      ),
    );

    await tester.pumpWidget(_host(controller));

    expect(find.byKey(const Key('serviceNoticeBanner')), findsNothing);
  });

  testWidgets('닫기를 누르면 배너가 사라진다', (tester) async {
    final controller = await _seed(
      tester,
      ActiveNoticesResult(notices: [_notice('n1')], stale: false),
    );

    await tester.pumpWidget(_host(controller));
    expect(find.byKey(const Key('serviceNoticeBanner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('serviceNoticeBannerDismiss')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('serviceNoticeBanner')), findsNothing);
  });

  testWidgets('배너 본문을 누르면 목록 열기 콜백이 호출된다', (tester) async {
    var opened = false;
    final controller = await _seed(
      tester,
      ActiveNoticesResult(notices: [_notice('n1')], stale: false),
    );

    await tester.pumpWidget(_host(controller, onTap: () => opened = true));
    await tester.tap(find.byKey(const Key('serviceNoticeBannerBody')));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
  });

  testWidgets('오프라인(stale)이면 "N시간 전 기준" 라벨을 붙인다', (tester) async {
    final controller = await _seed(
      tester,
      ActiveNoticesResult(
        notices: [_notice('n1')],
        stale: true,
        asOf: DateTime(2026, 7, 6, 9, 0, 0),
      ),
    );

    await tester.pumpWidget(_host(controller));

    expect(find.text('3시간 전 기준'), findsOneWidget);
  });
}
