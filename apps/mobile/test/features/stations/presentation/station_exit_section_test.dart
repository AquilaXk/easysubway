import 'package:easysubway_mobile/core/external/kakao_map_launcher.dart';
import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_exit_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('빈 출구 목록은 섹션 생성 시 거부한다', () {
    expect(
      () => StationExitSection(
        station: _station,
        exits: const [],
        mapLauncher: _RecordingMapLauncher(),
        locationProvider: null,
      ),
      throwsAssertionError,
    );
  });

  testWidgets('첫 출구를 선택하고 목록 경계에서 이전 다음 버튼을 막는다', (tester) async {
    await _pumpSection(tester);

    expect(find.text('preview-exit-1'), findsOneWidget);
    expect(find.byKey(const ValueKey('exit-1')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('stationExitPreviousButton')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('stationExitNextButton')))
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.byKey(const Key('stationExitNextButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('stationExitNextButton')));
    await tester.pump();

    expect(find.text('preview-exit-3'), findsOneWidget);
    expect(find.byKey(const ValueKey('exit-3')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('stationExitNextButton')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('dropdown과 버튼이 같은 선택 상태를 갱신한다', (tester) async {
    await _pumpSection(tester);

    await tester.tap(find.byKey(const Key('stationExitSelector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3번 출구').last);
    await tester.pumpAndSettle();

    expect(find.text('preview-exit-3'), findsOneWidget);
    expect(find.byKey(const ValueKey('exit-3')), findsOneWidget);

    await tester.tap(find.byKey(const Key('stationExitPreviousButton')));
    await tester.pump();

    expect(find.text('preview-exit-2'), findsOneWidget);
    expect(find.byKey(const ValueKey('exit-2')), findsOneWidget);
  });

  testWidgets('미리보기 탭은 현재 선택 출구를 기존 카카오맵 launcher로 연다', (tester) async {
    final launcher = _RecordingMapLauncher();
    await _pumpSection(tester, launcher: launcher);

    await tester.tap(find.byKey(const Key('stationExitNextButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('fakeMapPreviewButton')));
    await tester.pump();

    expect(launcher.lookTargets, hasLength(1));
    expect(launcher.lookTargets.single.label, '상록수역 2번 출구');
    expect(find.text('카카오맵을 열었습니다.'), findsOneWidget);
  });

  testWidgets('출구 목록이 바뀌면 새 목록의 첫 출구로 돌아간다', (tester) async {
    await _pumpSection(tester);
    await tester.tap(find.byKey(const Key('stationExitNextButton')));
    await tester.pump();
    expect(find.text('preview-exit-2'), findsOneWidget);

    await _pumpSection(tester, exits: [_exits[2], _exits[0]]);
    await tester.pump();

    expect(find.text('preview-exit-3'), findsOneWidget);
    expect(find.byKey(const ValueKey('exit-3')), findsOneWidget);
  });

  testWidgets('출구가 하나여도 큰 글자에서 선택기는 48dp 터치 영역을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSection(
      tester,
      exits: [_exits.first],
      textScaler: const TextScaler.linear(2),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('stationExitPreviousButton'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.byKey(const Key('stationExitNextButton'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('stationExitPreviousButton')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('stationExitNextButton')))
          .onPressed,
      isNull,
    );
  });
}

Future<void> _pumpSection(
  WidgetTester tester, {
  _RecordingMapLauncher? launcher,
  List<StationExitInfo> exits = _exits,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: SingleChildScrollView(
            child: StationExitSection(
              station: _station,
              exits: exits,
              mapLauncher: launcher ?? _RecordingMapLauncher(),
              locationProvider: null,
              mapPreviewBuilder:
                  ({
                    required station,
                    required exits,
                    required selectedExitId,
                    required onOpenSelected,
                  }) {
                    return TextButton(
                      key: const Key('fakeMapPreviewButton'),
                      onPressed: onOpenSelected,
                      child: Text('preview-$selectedExitId'),
                    );
                  },
            ),
          ),
        ),
      ),
    ),
  );
}

const _station = StationDetail(
  id: 'station-sangnoksu',
  nameKo: '상록수',
  nameEn: 'Sangnoksu',
  region: '수도권',
  latitude: 37.302795,
  longitude: 126.866489,
  dataQualityLevel: 'LEVEL_2',
  lastVerifiedAt: '2026-07-28',
  lines: [],
);

const _exits = [
  StationExitInfo(
    id: 'exit-1',
    stationId: 'station-sangnoksu',
    exitNumber: '1',
    name: '1번 출구',
    latitude: 37.301,
    longitude: 126.861,
    hasElevatorConnection: true,
    hasStairOnlyPath: false,
    dataConfidence: 'HIGH',
  ),
  StationExitInfo(
    id: 'exit-2',
    stationId: 'station-sangnoksu',
    exitNumber: '2',
    name: '2번 출구',
    latitude: 37.302,
    longitude: 126.862,
    hasElevatorConnection: false,
    hasStairOnlyPath: true,
    dataConfidence: 'HIGH',
  ),
  StationExitInfo(
    id: 'exit-3',
    stationId: 'station-sangnoksu',
    exitNumber: '3',
    name: '3번 출구',
    latitude: 37.303,
    longitude: 126.863,
    hasElevatorConnection: true,
    hasStairOnlyPath: false,
    dataConfidence: 'HIGH',
  ),
];

class _RecordingMapLauncher implements KakaoMapLauncher {
  final lookTargets = <KakaoMapTarget>[];

  @override
  Future<KakaoMapLaunchResult> openLook(KakaoMapTarget target) async {
    lookTargets.add(target);
    return KakaoMapLaunchResult.app;
  }

  @override
  Future<KakaoMapLaunchResult> openWalkingRoute(
    KakaoWalkingRouteTarget target,
  ) async {
    return KakaoMapLaunchResult.failed;
  }
}
