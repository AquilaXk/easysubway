import 'package:easysubway_mobile/accessible_design.dart';
import 'package:easysubway_mobile/features/notifications/presentation/new_notification_bar.dart';
import 'package:easysubway_mobile/features/service_notice/data/notice_repository.dart';
import 'package:easysubway_mobile/features/service_notice/domain/service_notice.dart';
import 'package:easysubway_mobile/features/service_notice/presentation/notice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ServiceNotice _disruption(String id) {
  return ServiceNotice(
    id: id,
    scope: NoticeScope.all,
    title: '제목 $id',
    body: '본문 $id',
    severity: NoticeSeverity.disruption,
    publishedAt: DateTime(2026, 7, 16, 9, 0, 0),
  );
}

class _FakeRepository implements NoticeRepository {
  _FakeRepository(this.result);
  final ActiveNoticesResult result;
  @override
  Future<ActiveNoticesResult> activeNotices() async => result;
}

Future<NoticeController> _seed(ActiveNoticesResult result) async {
  final controller = NoticeController(repository: _FakeRepository(result));
  await controller.refresh();
  return controller;
}

Widget _host({
  NoticeController? noticeController,
  required bool hasNotificationItems,
  VoidCallback? onOpenInbox,
}) {
  return MaterialApp(
    home: Scaffold(
      body: NewNotificationBar(
        noticeController: noticeController,
        hasNotificationItems: hasNotificationItems,
        onOpenInbox: onOpenInbox ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('운행 공지 disruption만 있어도 바를 표시한다', (tester) async {
    final controller = await _seed(
      ActiveNoticesResult(notices: [_disruption('n1')], stale: false),
    );

    await tester.pumpWidget(
      _host(noticeController: controller, hasNotificationItems: false),
    );

    expect(find.byKey(const Key('newNotificationBar')), findsOneWidget);
    expect(find.text('새로운 알림이 있어요'), findsOneWidget);
    expect(find.text('알림 보기'), findsOneWidget);
  });

  testWidgets('알림함 새 항목만 있어도 바를 표시한다', (tester) async {
    await tester.pumpWidget(_host(hasNotificationItems: true));

    expect(find.byKey(const Key('newNotificationBar')), findsOneWidget);
  });

  testWidgets('알림이 없으면 바도 여백도 그리지 않는다', (tester) async {
    final controller = await _seed(
      ActiveNoticesResult(
        notices: [
          ServiceNotice(
            id: 'i1',
            scope: NoticeScope.all,
            title: '정보',
            body: '본문',
            severity: NoticeSeverity.info,
            publishedAt: DateTime(2026, 7, 16, 9, 0, 0),
          ),
        ],
        stale: false,
      ),
    );

    await tester.pumpWidget(
      _host(noticeController: controller, hasNotificationItems: false),
    );

    expect(find.byKey(const Key('newNotificationBar')), findsNothing);
    expect(find.text('새로운 알림이 있어요'), findsNothing);
    // 빈 공간 없이 shrink.
    final shrink = tester.widget<SizedBox>(
      find.descendant(
        of: find.byType(NewNotificationBar),
        matching: find.byType(SizedBox),
      ),
    );
    expect(shrink.height, 0);
    expect(shrink.width, 0);
  });

  testWidgets('바를 한 번 탭하면 onOpenInbox가 정확히 1회만 호출된다 (이중 실행 회귀)', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(hasNotificationItems: true, onOpenInbox: () => calls++),
    );

    await tester.tap(find.byKey(const Key('newNotificationBar')));
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('바는 radius 0·margin 0·그림자 없음이고 최소 높이 48이다', (tester) async {
    await tester.pumpWidget(_host(hasNotificationItems: true));

    // margin 0: 바가 화면 전체 너비를 차지한다.
    final barSize = tester.getSize(find.byKey(const Key('newNotificationBar')));
    final screenWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    expect(barSize.width, screenWidth);
    expect(barSize.height, greaterThanOrEqualTo(48));

    // 그림자 없음·radius 0: elevation 0, borderRadius 미지정, 표면색은 토큰.
    final material = tester.widget<Material>(
      find.byKey(const Key('newNotificationBar')),
    );
    expect(material.elevation, 0);
    expect(material.borderRadius, isNull);
    expect(material.color, EasySubwayAccessibleColors.noticeBarSurface);
  });
}
