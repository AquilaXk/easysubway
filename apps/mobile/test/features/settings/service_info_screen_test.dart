import 'dart:ui';

import 'package:easysubway_mobile/features/settings/presentation/service_info_screen.dart';
import 'package:easysubway_mobile/features/settings/presentation/open_source_licenses_screen.dart';
import 'package:easysubway_mobile/features/support/presentation/support_access_screen.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const accessInfo = SupportAccessInfo(
    termsOfServiceUrl: 'https://easysubway.example/terms',
    privacyPolicyUrl: 'https://easysubway.example/privacy',
    locationTermsUrl: 'https://easysubway.example/location-terms',
    supportEmail: 'support@easysubway.example',
    dataDeletionEmail: 'privacy@easysubway.example',
  );

  testWidgets('서비스 정보는 고정된 5개 항목을 순서대로 표시한다', (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ServiceInfoScreen(
          accessInfo: accessInfo,
          supportsInAppBrowser: () async => true,
          launchInAppBrowser: (uri) async {
            opened.add(uri);
            return true;
          },
        ),
      ),
    );

    final labels = [
      '서비스 이용약관',
      '개인정보 처리방침',
      '위치정보 이용약관',
      '정보제공처',
      '오픈 소스 라이선스',
    ];
    for (final label in labels) {
      expect(find.text(label), findsOneWidget);
    }
    final centers = labels.map(
      (label) => tester.getCenter(find.text(label)).dy,
    );
    expect(centers, orderedEquals(centers.toList()..sort()));

    await tester.tap(find.text('서비스 이용약관'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://easysubway.example/terms')]);
  });

  testWidgets('문서 열기 실패는 외부 우회 없이 같은 오류를 표시한다', (tester) async {
    final reportedErrors = <FlutterErrorDetails>[];
    await runWithMobileErrorReporter(reportedErrors.add, () async {
      for (final failure in <Future<bool> Function(Uri)>[
        (_) async => false,
        (_) async => throw StateError('launch failed'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: ServiceInfoScreen(
              accessInfo: accessInfo,
              supportsInAppBrowser: () async => true,
              launchInAppBrowser: failure,
            ),
          ),
        );
        await tester.tap(find.text('개인정보 처리방침'));
        await tester.pumpAndSettle();
        expect(find.text('문서를 열 수 없어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ServiceInfoScreen(
            accessInfo: accessInfo,
            supportsInAppBrowser: () async => false,
            launchInAppBrowser: (_) async => true,
          ),
        ),
      );
      await tester.tap(find.text('위치정보 이용약관'));
      await tester.pumpAndSettle();
      expect(find.text('문서를 열 수 없어요. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    });

    expect(reportedErrors, hasLength(3));
    expect(
      reportedErrors.every(
        (details) =>
            details.context?.toDescription().contains('서비스 정보 법적 문서 열기') ??
            false,
      ),
      isTrue,
    );
  });

  testWidgets('360px 화면과 200% 글자 크기에서도 모든 항목을 조작할 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: ServiceInfoScreen(
            accessInfo: accessInfo,
            supportsInAppBrowser: () async => true,
            launchInAppBrowser: (_) async => true,
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('openSourceLicensesItem')),
      120,
    );
    expect(tester.takeException(), isNull);
    for (final key in const [
      'termsOfServiceItem',
      'privacyPolicyItem',
      'locationTermsItem',
      'dataSourceAttributionItem',
      'openSourceLicensesItem',
    ]) {
      final finder = find.byKey(Key(key));
      await tester.scrollUntilVisible(finder, 120);
      final semantics = tester.getSemantics(finder).getSemanticsData();
      expect(semantics.hasAction(SemanticsAction.tap), isTrue);
      expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('정보제공처와 오픈 소스 라이선스는 앱 내부 화면으로 이동한다', (tester) async {
    Future<List<LicenseEntry>> loadLicenses() async => const [
      LicenseEntryWithLineBreaks([
        'sample_package',
      ], 'Copyright 2026 Sample Authors.\n\nSample license text.'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: ServiceInfoScreen(
          accessInfo: accessInfo,
          supportsInAppBrowser: () async => true,
          launchInAppBrowser: (_) async => true,
          licenseEntriesLoader: loadLicenses,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('dataSourceAttributionItem')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const Key('dataSourceAttributionScreen')),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openSourceLicensesItem')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('openSourceLicensesScreen')), findsOneWidget);
    expect(find.text('OSS Notice | EasySubway'), findsOneWidget);
    expect(find.text('sample_package'), findsOneWidget);

    await tester.tap(find.text('sample_package'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Copyright 2026 Sample Authors.'),
      findsOneWidget,
    );
    expect(find.textContaining('Sample license text.'), findsOneWidget);
    expect(find.byType(LicensePage), findsNothing);
  });

  testWidgets('오픈 소스 정보는 빈 목록과 수집 실패를 앱 내부에서 설명한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: OpenSourceLicensesScreen(
          key: const Key('emptyLicenses'),
          licenseEntriesLoader: () async => const [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('등록된 오픈 소스 고지가 없어요.'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: OpenSourceLicensesScreen(
          key: const Key('failedLicenses'),
          licenseEntriesLoader: () async =>
              throw StateError('license registry failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('오픈 소스 정보를 불러오지 못했어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('오픈 소스 전문은 360px와 200% 글자에서도 세로로 읽을 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: OpenSourceLicensesScreen(
            licenseEntriesLoader: () async => const [
              LicenseEntryWithLineBreaks(
                ['accessible_package'],
                'Copyright Accessible Authors.\n\nA complete license paragraph that wraps on a compact screen.',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('accessible_package'), 120);
    await tester.tap(find.text('accessible_package'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('A complete license paragraph'),
      120,
    );

    expect(find.textContaining('A complete license paragraph'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
