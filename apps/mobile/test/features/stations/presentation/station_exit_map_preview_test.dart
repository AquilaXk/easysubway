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
    expect(
      find.bySemanticsLabel('1번 출구 카카오맵에서 보기, 출구 좌표가 없어 역 위치 기준으로 새 앱이 열립니다'),
      findsOneWidget,
    );
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
}

Future<void> _pumpPreview(
  WidgetTester tester, {
  StationDetail? station,
  List<StationExitInfo>? exits,
  String nativeAppKey = 'test-native-map-key',
  VoidCallback? onOpenSelected,
  StationExitNativeMapBuilder? nativeMapBuilder,
}) {
  final resolvedExits =
      exits ??
      [_exit(id: 'exit-1', number: '1', latitude: 37.301, longitude: 126.861)];
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StationExitMapPreview(
          station: station ?? _station(),
          exits: resolvedExits,
          selectedExitId: resolvedExits.first.id,
          onOpenSelected: onOpenSelected ?? () {},
          nativeAppKey: nativeAppKey,
          nativeMapBuilder: nativeMapBuilder,
        ),
      ),
    ),
  );
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
