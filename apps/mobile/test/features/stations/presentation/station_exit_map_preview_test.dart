import 'dart:async';

import 'package:easysubway_mobile/features/stations/domain/station_models.dart';
import 'package:easysubway_mobile/features/stations/presentation/station_exit_map_preview.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

void main() {
  test('좌표 쌍이 있는 출구만 API 순서대로 미리보기 point가 된다', () {
    final points = stationExitPreviewPoints([
      _exit(id: 'exit-2', number: '2', latitude: 37.2, longitude: 126.2),
      _exit(id: 'exit-1', number: '1', latitude: 37.1),
      _exit(id: 'exit-3', number: '3', latitude: 37.3, longitude: 126.3),
    ]);

    expect(points, [
      (id: 'exit-2', number: '2', latitude: 37.2, longitude: 126.2),
      (id: 'exit-3', number: '3', latitude: 37.3, longitude: 126.3),
    ]);
  });

  testWidgets('개발 key가 없으면 native map 대신 unavailable 안내를 보여준다', (tester) async {
    var mapBuildCount = 0;
    await _pumpPreview(
      tester,
      nativeAppKey: '',
      nativeMapBuilder: _recordingMapBuilder(onBuild: (_) => mapBuildCount++),
    );

    expect(find.text('지도 미리보기를 사용할 수 없어요.'), findsOneWidget);
    expect(find.text('아래 카카오맵에서 보기 버튼은 계속 사용할 수 있어요.'), findsOneWidget);
    expect(mapBuildCount, 0);
  });

  testWidgets('출구와 역 좌표가 모두 없으면 미리보기를 생략한다', (tester) async {
    var mapBuildCount = 0;
    await _pumpPreview(
      tester,
      station: _station(latitude: null, longitude: null),
      exits: [_exit(id: 'exit-1', number: '1')],
      nativeMapBuilder: _recordingMapBuilder(onBuild: (_) => mapBuildCount++),
    );

    expect(find.byKey(const Key('stationExitMapPreview')), findsNothing);
    expect(find.textContaining('지도 미리보기'), findsNothing);
    expect(mapBuildCount, 0);
  });

  testWidgets('출구 좌표가 없으면 역 좌표와 zoom 16으로 지도를 시작한다', (tester) async {
    KakaoMapOption? capturedOption;
    await _pumpPreview(
      tester,
      exits: [_exit(id: 'exit-1', number: '1')],
      nativeMapBuilder: _recordingMapBuilder(
        onBuild: (option) => capturedOption = option,
      ),
    );

    expect(capturedOption, isNotNull);
    expect(capturedOption!.position.latitude, 37.302795);
    expect(capturedOption!.position.longitude, 126.866489);
    expect(capturedOption!.zoomLevel, 16);
    expect(capturedOption!.viewName, isNull);
    expect(
      find.bySemanticsLabel('1번 출구 카카오맵에서 보기, 출구 좌표가 없어 역 위치 기준으로 새 앱이 열립니다'),
      findsOneWidget,
    );
  });

  testWidgets('선택 출구 좌표만 없으면 역 fallback marker를 지도에 포함한다', (tester) async {
    final controller = _FakeKakaoMapController();
    await _pumpPreview(
      tester,
      exits: [
        _exit(id: 'exit-1', number: '1', latitude: 37.301, longitude: 126.861),
        _exit(id: 'exit-2', number: '2'),
      ],
      selectedExitId: 'exit-2',
      nativeMapBuilder: _readyMapBuilder(controller),
    );
    await _pumpUntil(
      tester,
      () => controller.labels.addPoiCount >= 2,
      reason: '선택 출구 fallback marker까지 준비되어야 한다',
    );

    expect(controller.labels.positions['exit-2']!.latitude, 37.302795);
    expect(controller.labels.positions['exit-2']!.longitude, 126.866489);
  });

  testWidgets('SDK 오류는 다시 시도 가능한 안내로 바뀐다', (tester) async {
    final keys = <Key>[];
    final reportedErrors = <FlutterErrorDetails>[];
    void Function(Error)? reportError;
    await _pumpPreview(
      tester,
      nativeMapBuilder:
          ({
            required key,
            required option,
            required onMapReady,
            required onMapError,
          }) {
            keys.add(key);
            reportError = onMapError;
            return const ColoredBox(color: Colors.grey);
          },
    );

    await runWithMobileErrorReporter(
      (details) => reportedErrors.add(details),
      () async {
        reportError!(_FakeMapError());
        await tester.pump();
      },
    );

    expect(find.text('지도 미리보기를 불러오지 못했어요.'), findsOneWidget);
    expect(
      reportedErrors.single.exception.toString(),
      contains('_FakeMapError'),
    );
    await tester.tap(find.widgetWithText(TextButton, '다시 시도'));
    await tester.pump();

    expect(keys, hasLength(2));
    expect(keys[0], isNot(keys[1]));
  });

  testWidgets('지도 구성 실패는 controller를 종료한다', (tester) async {
    final controller = _FakeKakaoMapController(failSetClickable: true);

    await runWithMobileErrorReporter((_) {}, () async {
      await _pumpPreview(
        tester,
        nativeMapBuilder: _readyMapBuilder(controller),
      );
      await _pumpUntil(
        tester,
        () => controller.finishCount == 1,
        reason: '구성 실패 뒤 controller가 종료되어야 한다',
      );
      await tester.pump();
    });

    expect(find.text('지도 미리보기를 불러오지 못했어요.'), findsOneWidget);
  });

  testWidgets('SDK 오류는 진행 중인 지도 구성을 중단한다', (tester) async {
    final firstPoiGate = Completer<void>();
    final controller = _FakeKakaoMapController(firstPoiGate: firstPoiGate);
    late ValueChanged<Error> reportError;

    await _pumpPreview(
      tester,
      exits: [
        _exit(id: 'exit-1', number: '1', latitude: 37.301, longitude: 126.861),
        _exit(id: 'exit-2', number: '2', latitude: 37.302, longitude: 126.862),
      ],
      nativeMapBuilder:
          ({
            required key,
            required option,
            required onMapReady,
            required onMapError,
          }) {
            reportError = onMapError;
            return _MapReadyStub(
              key: key,
              controller: controller,
              onReady: onMapReady,
            );
          },
    );
    await _pumpUntil(
      tester,
      () => controller.labels.addPoiCount == 1,
      reason: '첫 marker 구성이 시작되어야 한다',
    );

    await runWithMobileErrorReporter((_) {}, () async {
      reportError(_FakeMapError());
      await tester.pump();
    });
    firstPoiGate.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(controller.labels.addPoiCount, 1);
    expect(controller.moveCameraCount, 0);
  });

  testWidgets('SDK 오류 안내는 live region으로 전환된다', (tester) async {
    final semanticsHandle = tester.ensureSemantics();
    void Function(Error)? reportError;
    await _pumpPreview(
      tester,
      nativeMapBuilder:
          ({
            required key,
            required option,
            required onMapReady,
            required onMapError,
          }) {
            reportError = onMapError;
            return const ColoredBox(color: Colors.grey);
          },
    );

    await runWithMobileErrorReporter((_) {}, () async {
      reportError!(_FakeMapError());
      await tester.pump();
    });

    expect(
      tester.getSemantics(
        find.bySemanticsLabel('지도 미리보기를 불러오지 못했어요. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.'),
      ),
      isSemantics(
        label: '지도 미리보기를 불러오지 못했어요. 네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
        isLiveRegion: true,
      ),
    );
    semanticsHandle.dispose();
  });

  testWidgets('SDK 오류 안내는 큰 글자에서 144dp보다 높게 확장된다', (tester) async {
    void Function(Error)? reportError;
    await _pumpPreview(
      tester,
      textScaler: const TextScaler.linear(3),
      nativeMapBuilder:
          ({
            required key,
            required option,
            required onMapReady,
            required onMapError,
          }) {
            reportError = onMapError;
            return const ColoredBox(color: Colors.grey);
          },
    );

    await runWithMobileErrorReporter((_) {}, () async {
      reportError!(_FakeMapError());
      await tester.pump();
    });

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('stationExitMapPreview'))).height,
      greaterThan(144),
    );
  });

  testWidgets('미리보기 전체 탭은 선택 출구 callback을 호출한다', (tester) async {
    var openCount = 0;
    await _pumpPreview(
      tester,
      onOpenSelected: () => openCount++,
      nativeMapBuilder: _recordingMapBuilder(onBuild: (_) {}),
    );

    await tester.tap(find.bySemanticsLabel('상록수역 1번 출구 카카오맵에서 보기, 새 앱이 열립니다'));
    await tester.pump();

    expect(openCount, 1);
  });

  testWidgets('native map semantics는 미리보기 열기 버튼 하나로 대체한다', (tester) async {
    await _pumpPreview(
      tester,
      nativeMapBuilder:
          ({
            required key,
            required option,
            required onMapReady,
            required onMapError,
          }) => Semantics(
            key: key,
            label: 'native map internal',
            child: const ColoredBox(color: Colors.grey),
          ),
    );

    expect(find.bySemanticsLabel('native map internal'), findsNothing);
    expect(
      find.bySemanticsLabel('상록수역 1번 출구 카카오맵에서 보기, 새 앱이 열립니다'),
      findsOneWidget,
    );
  });

  testWidgets('route가 가려지면 지도를 멈추고 다시 보이면 재개한다', (tester) async {
    final controller = _FakeKakaoMapController();
    var routeVisible = true;
    late StateSetter updateHost;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return TickerMode(
              enabled: routeVisible,
              child: Scaffold(
                body: StationExitMapPreview(
                  station: _station(),
                  exits: [
                    _exit(
                      id: 'exit-1',
                      number: '1',
                      latitude: 37.301,
                      longitude: 126.861,
                    ),
                  ],
                  selectedExitId: 'exit-1',
                  onOpenSelected: () {},
                  nativeAppKey: 'test-native-map-key',
                  nativeMapBuilder: _readyMapBuilder(controller),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();

    updateHost(() => routeVisible = false);
    await tester.pump();
    expect(controller.pauseCount, 1);

    updateHost(() => routeVisible = true);
    await tester.pump();
    expect(controller.resumeCount, 1);
  });

  testWidgets('가려진 route는 foreground 복귀 뒤에도 지도를 멈춘다', (tester) async {
    final controller = _FakeKakaoMapController();
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: Scaffold(
            body: StationExitMapPreview(
              station: _station(),
              exits: [
                _exit(
                  id: 'exit-1',
                  number: '1',
                  latitude: 37.301,
                  longitude: 126.861,
                ),
              ],
              selectedExitId: 'exit-1',
              onOpenSelected: () {},
              nativeAppKey: 'test-native-map-key',
              nativeMapBuilder: _readyMapBuilder(controller),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final initialPauseCount = controller.pauseCount;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(controller.resumeCount, 0);
    expect(controller.pauseCount, greaterThan(initialPauseCount));
  });

  testWidgets('지도 구성 중 출구를 바꿔도 현재 출구 marker만 강조한다', (tester) async {
    final firstPoiGate = Completer<void>();
    final controller = _FakeKakaoMapController(firstPoiGate: firstPoiGate);
    var selectedExitId = 'exit-1';
    late StateSetter updateHost;
    final exits = [
      _exit(id: 'exit-1', number: '1', latitude: 37.301, longitude: 126.861),
      _exit(id: 'exit-2', number: '2', latitude: 37.302, longitude: 126.862),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: StationExitMapPreview(
                station: _station(),
                exits: exits,
                selectedExitId: selectedExitId,
                onOpenSelected: () {},
                nativeAppKey: 'test-native-map-key',
                nativeMapBuilder: _readyMapBuilder(controller),
              ),
            );
          },
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await _pumpUntil(
      tester,
      () => controller.labels.addPoiCount > 0,
      reason: '첫 marker 구성이 시작되어야 한다',
    );
    expect(controller.labels.addPoiCount, 1);

    updateHost(() => selectedExitId = 'exit-2');
    await tester.pump();
    firstPoiGate.complete();
    await _pumpUntil(
      tester,
      () => controller.labels.changeStyleCount >= 2,
      reason: '현재 선택으로 marker style이 수렴해야 한다',
    );
    await tester.pumpAndSettle();

    expect(controller.labels.changeStyleCount, 2);
    expect(controller.labels.pois['exit-1']!.lastStyle.icon!.width, 32);
    expect(controller.labels.pois['exit-2']!.lastStyle.icon!.width, 36);
  });

  testWidgets('빠르게 출구를 왕복 선택해도 마지막 선택 marker만 강조한다', (tester) async {
    final controller = _FakeKakaoMapController();
    var selectedExitId = 'exit-1';
    late StateSetter updateHost;
    final exits = [
      _exit(id: 'exit-1', number: '1', latitude: 37.301, longitude: 126.861),
      _exit(id: 'exit-2', number: '2', latitude: 37.302, longitude: 126.862),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: StationExitMapPreview(
                station: _station(),
                exits: exits,
                selectedExitId: selectedExitId,
                onOpenSelected: () {},
                nativeAppKey: 'test-native-map-key',
                nativeMapBuilder: _readyMapBuilder(controller),
              ),
            );
          },
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => controller.labels.addPoiCount >= 2,
      reason: '선택 변경 전 marker 두 개가 준비되어야 한다',
    );
    final delayedOldChange = Completer<void>();
    controller.labels.pois['exit-1']!.nextChangeGate = delayedOldChange;

    updateHost(() => selectedExitId = 'exit-2');
    await tester.pump();
    updateHost(() => selectedExitId = 'exit-1');
    await tester.pump();
    delayedOldChange.complete();
    await _pumpUntil(
      tester,
      () => controller.labels.changeStyleCount >= 4,
      reason: '연속 선택 변경의 style 작업이 완료되어야 한다',
    );
    await tester.pumpAndSettle();

    expect(controller.labels.changeStyleCount, greaterThanOrEqualTo(4));
    expect(controller.labels.pois['exit-1']!.lastStyle.icon!.width, 36);
    expect(controller.labels.pois['exit-2']!.lastStyle.icon!.width, 32);
  });

  testWidgets('위젯이 제거되면 진행 중인 marker style 동기화를 멈춘다', (tester) async {
    final controller = _FakeKakaoMapController();
    var selectedExitId = 'exit-1';
    final exits = [
      _exit(id: 'exit-1', number: '1', latitude: 37.301, longitude: 126.861),
      _exit(id: 'exit-2', number: '2', latitude: 37.302, longitude: 126.862),
    ];
    late StateSetter updateHost;
    final reportedErrors = <FlutterErrorDetails>[];

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: StationExitMapPreview(
                station: _station(),
                exits: exits,
                selectedExitId: selectedExitId,
                onOpenSelected: () {},
                nativeAppKey: 'test-native-map-key',
                nativeMapBuilder: _readyMapBuilder(controller),
              ),
            );
          },
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => controller.labels.addPoiCount == 2,
      reason: '초기 marker 두 개가 준비되어야 한다',
    );
    final oldStyleGate = Completer<void>();
    controller.labels.pois['exit-1']!.nextChangeGate = oldStyleGate;

    await runWithMobileErrorReporter(
      (details) => reportedErrors.add(details),
      () async {
        updateHost(() => selectedExitId = 'exit-2');
        await tester.pump();
        await _pumpUntil(
          tester,
          () => controller.labels.pois['exit-1']!.nextChangeGate == null,
          reason: '첫 marker style 변경이 시작되어야 한다',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        oldStyleGate.complete();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      },
    );

    expect(controller.finishCount, 1);
    expect(reportedErrors, isEmpty);
    expect(controller.labels.pois['exit-2']!.changeStyleCount, 0);
  });

  testWidgets('카메라 이동 중 출구를 바꿔도 현재 선택 marker로 수렴한다', (tester) async {
    final moveCameraGate = Completer<void>();
    final controller = _FakeKakaoMapController(moveCameraGate: moveCameraGate);
    var selectedExitId = 'exit-1';
    late StateSetter updateHost;
    final exits = [
      _exit(id: 'exit-1', number: '1', latitude: 37.301, longitude: 126.861),
      _exit(id: 'exit-2', number: '2', latitude: 37.302, longitude: 126.862),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: StationExitMapPreview(
                station: _station(),
                exits: exits,
                selectedExitId: selectedExitId,
                onOpenSelected: () {},
                nativeAppKey: 'test-native-map-key',
                nativeMapBuilder: _readyMapBuilder(controller),
              ),
            );
          },
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => controller.moveCameraCount > 0,
      reason: '카메라 이동이 시작되어야 한다',
    );
    expect(controller.moveCameraCount, 1);

    updateHost(() => selectedExitId = 'exit-2');
    await tester.pump();
    moveCameraGate.complete();
    await _pumpUntil(
      tester,
      () => controller.labels.changeStyleCount >= 2,
      reason: '카메라 이동 뒤 선택 style이 수렴해야 한다',
    );
    await tester.pumpAndSettle();

    expect(controller.labels.pois['exit-1']!.lastStyle.icon!.width, 32);
    expect(controller.labels.pois['exit-2']!.lastStyle.icon!.width, 36);
  });

  testWidgets('재시도 전 addPoi 결과가 새 지도 marker를 덮어쓰지 않는다', (tester) async {
    final firstPoiGate = Completer<void>();
    final oldController = _FakeKakaoMapController(firstPoiGate: firstPoiGate);
    final newController = _FakeKakaoMapController();
    final exits = [
      _exit(id: 'exit-1', number: '1', latitude: 37.301, longitude: 126.861),
      _exit(id: 'exit-2', number: '2', latitude: 37.302, longitude: 126.862),
    ];
    var selectedExitId = 'exit-1';
    var buildCount = 0;
    late StateSetter updateHost;
    late ValueChanged<Error> failMap;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return Scaffold(
              body: StationExitMapPreview(
                station: _station(),
                exits: exits,
                selectedExitId: selectedExitId,
                onOpenSelected: () {},
                nativeAppKey: 'test-native-map-key',
                nativeMapBuilder:
                    ({
                      required key,
                      required option,
                      required onMapReady,
                      required onMapError,
                    }) {
                      buildCount++;
                      failMap = onMapError;
                      return _MapReadyStub(
                        key: key,
                        controller: buildCount == 1
                            ? oldController
                            : newController,
                        onReady: onMapReady,
                      );
                    },
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await _pumpUntil(
      tester,
      () => oldController.labels.addPoiCount > 0,
      reason: '이전 지도의 marker 구성이 시작되어야 한다',
    );

    await runWithMobileErrorReporter((_) {}, () async {
      failMap(_FakeMapError());
      await tester.pump();
    });
    await tester.tap(find.widgetWithText(TextButton, '다시 시도'));
    await tester.pump();
    await _pumpUntil(
      tester,
      () => newController.labels.addPoiCount >= 2,
      reason: '재시도한 지도의 marker 두 개가 준비되어야 한다',
    );

    firstPoiGate.complete();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    updateHost(() => selectedExitId = 'exit-2');
    await tester.pump();
    await _pumpUntil(
      tester,
      () => newController.labels.changeStyleCount >= 2,
      reason: '재시도한 지도의 선택 style이 수렴해야 한다',
    );

    expect(newController.labels.pois['exit-1']!.lastStyle.icon!.width, 32);
    expect(newController.labels.pois['exit-2']!.lastStyle.icon!.width, 36);
  });

  testWidgets('재시도 전 지도 late callback은 새 지도를 건드리지 않는다', (tester) async {
    final readyCallbacks = <ValueChanged<KakaoMapController>>[];
    final errorCallbacks = <ValueChanged<Error>>[];
    final oldController = _FakeKakaoMapController();
    final newController = _FakeKakaoMapController();

    await _pumpPreview(
      tester,
      nativeMapBuilder:
          ({
            required key,
            required option,
            required onMapReady,
            required onMapError,
          }) {
            readyCallbacks.add(onMapReady);
            errorCallbacks.add(onMapError);
            return ColoredBox(key: key, color: Colors.grey);
          },
    );

    await runWithMobileErrorReporter((_) {}, () async {
      errorCallbacks.first(_FakeMapError());
      await tester.pump();
    });
    await tester.tap(find.widgetWithText(TextButton, '다시 시도'));
    await tester.pump();
    readyCallbacks.last(newController);
    await tester.pump();

    readyCallbacks.first(oldController);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    await runWithMobileErrorReporter((_) {}, () async {
      errorCallbacks.first(_FakeMapError());
      await tester.pump();
    });

    expect(oldController.labels.addPoiCount, 0);
    expect(newController.finishCount, 0);
    expect(find.text('지도 미리보기를 불러오지 못했어요.'), findsNothing);
  });
}

Future<void> _pumpPreview(
  WidgetTester tester, {
  StationDetail? station,
  List<StationExitInfo>? exits,
  String? selectedExitId,
  String nativeAppKey = 'test-native-map-key',
  TextScaler textScaler = TextScaler.noScaling,
  VoidCallback? onOpenSelected,
  StationExitNativeMapBuilder? nativeMapBuilder,
}) {
  final resolvedExits =
      exits ??
      [_exit(id: 'exit-1', number: '1', latitude: 37.301, longitude: 126.861)];
  return tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: Scaffold(
          body: StationExitMapPreview(
            station: station ?? _station(),
            exits: resolvedExits,
            selectedExitId: selectedExitId ?? resolvedExits.first.id,
            onOpenSelected: onOpenSelected ?? () {},
            nativeAppKey: nativeAppKey,
            nativeMapBuilder: nativeMapBuilder,
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  int attempts = 10,
}) async {
  for (var attempt = 0; attempt < attempts && !condition(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(condition(), isTrue, reason: reason);
}

StationExitNativeMapBuilder _recordingMapBuilder({
  required ValueChanged<KakaoMapOption> onBuild,
}) {
  return ({
    required key,
    required option,
    required onMapReady,
    required onMapError,
  }) {
    onBuild(option);
    return ColoredBox(key: key, color: Colors.grey);
  };
}

StationDetail _station({
  double? latitude = 37.302795,
  double? longitude = 126.866489,
}) {
  return StationDetail(
    id: 'station-sangnoksu',
    nameKo: '상록수',
    nameEn: 'Sangnoksu',
    region: '수도권',
    latitude: latitude,
    longitude: longitude,
    dataQualityLevel: 'LEVEL_2',
    lastVerifiedAt: '2026-07-28',
    lines: const [],
  );
}

StationExitInfo _exit({
  required String id,
  required String number,
  double? latitude,
  double? longitude,
}) {
  return StationExitInfo(
    id: id,
    stationId: 'station-sangnoksu',
    exitNumber: number,
    name: '$number번 출구',
    latitude: latitude,
    longitude: longitude,
    hasElevatorConnection: true,
    hasStairOnlyPath: false,
    dataConfidence: 'HIGH',
  );
}

final class _FakeMapError extends Error {}

StationExitNativeMapBuilder _readyMapBuilder(
  _FakeKakaoMapController controller,
) {
  return ({
    required key,
    required option,
    required onMapReady,
    required onMapError,
  }) => _MapReadyStub(key: key, controller: controller, onReady: onMapReady);
}

class _MapReadyStub extends StatefulWidget {
  const _MapReadyStub({
    required this.controller,
    required this.onReady,
    super.key,
  });

  final KakaoMapController controller;
  final ValueChanged<KakaoMapController> onReady;

  @override
  State<_MapReadyStub> createState() => _MapReadyStubState();
}

class _MapReadyStubState extends State<_MapReadyStub> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onReady(widget.controller);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.grey);
}

final class _FakeKakaoMapController implements KakaoMapController {
  _FakeKakaoMapController({
    Completer<void>? firstPoiGate,
    this.moveCameraGate,
    bool failSetClickable = false,
  }) : labels = _FakeLabelController(
         firstPoiGate: firstPoiGate,
         failSetClickable: failSetClickable,
       );

  final _FakeLabelController labels;
  final Completer<void>? moveCameraGate;
  int pauseCount = 0;
  int resumeCount = 0;
  int moveCameraCount = 0;
  int finishCount = 0;

  @override
  LabelController get labelLayer => labels;

  @override
  Future<void> setGesture(GestureType gesture, bool enable) async {}

  @override
  Future<void> moveCamera(
    CameraUpdate camera, {
    CameraAnimation? animation,
  }) async {
    moveCameraCount++;
    await moveCameraGate?.future;
  }

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> resume() async => resumeCount++;

  @override
  Future<void> finish() async => finishCount++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeLabelController implements LabelController {
  _FakeLabelController({this.firstPoiGate, this.failSetClickable = false});

  final Completer<void>? firstPoiGate;
  final bool failSetClickable;
  final pois = <String, _FakePoi>{};
  final positions = <String, LatLng>{};
  int addPoiCount = 0;
  int get changeStyleCount =>
      pois.values.fold(0, (count, poi) => count + poi.changeStyleCount);

  @override
  Future<void> setClickable(bool clickable) async {
    if (failSetClickable) {
      throw StateError('setClickable failed');
    }
  }

  @override
  Future<Poi> addPoi(
    LatLng position, {
    required PoiStyle style,
    String? id,
    String? text,
    TransformMethod? transform,
    int? rank,
    VoidCallback? onClick,
    bool visible = true,
  }) async {
    addPoiCount++;
    if (addPoiCount == 1) {
      await firstPoiGate?.future;
    }
    final poi = _FakePoi(style);
    pois[id!] = poi;
    positions[id] = position;
    return poi;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakePoi implements Poi {
  _FakePoi(this.lastStyle);

  PoiStyle lastStyle;
  int changeStyleCount = 0;
  Completer<void>? nextChangeGate;

  @override
  Future<void> changeStyles(PoiStyle style, [bool transition = false]) async {
    final gate = nextChangeGate;
    nextChangeGate = null;
    await gate?.future;
    lastStyle = style;
    changeStyleCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
