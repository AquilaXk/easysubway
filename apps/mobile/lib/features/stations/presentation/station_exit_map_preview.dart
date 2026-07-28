import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kakao_map_sdk/kakao_map_sdk.dart';

import '../../../core/external/kakao_map_configuration.dart';
import '../../../mobile_error_reporter.dart';
import '../domain/station_models.dart';
import 'station_exit_map_target.dart';

typedef StationExitPreviewPoint = ({
  String id,
  String number,
  double latitude,
  double longitude,
});

typedef StationExitNativeMapBuilder =
    Widget Function({
      required Key key,
      required KakaoMapOption option,
      required ValueChanged<KakaoMapController> onMapReady,
      required ValueChanged<Error> onMapError,
    });

List<StationExitPreviewPoint> stationExitPreviewPoints(
  List<StationExitInfo> exits,
) {
  return [
    for (final exit in exits)
      if (exit.latitude case final latitude?)
        if (exit.longitude case final longitude?)
          (
            id: exit.id,
            number: exit.exitNumber,
            latitude: latitude,
            longitude: longitude,
          ),
  ];
}

bool canShowStationExitMapPreview({
  required StationDetail station,
  required List<StationExitInfo> exits,
}) {
  return stationExitPreviewPoints(exits).isNotEmpty ||
      (station.latitude != null && station.longitude != null);
}

class StationExitMapPreview extends StatefulWidget {
  const StationExitMapPreview({
    required this.station,
    required this.exits,
    required this.selectedExitId,
    required this.onOpenSelected,
    this.nativeAppKey = kakaoMapNativeAppKey,
    this.nativeMapBuilder,
    super.key,
  });

  final StationDetail station;
  final List<StationExitInfo> exits;
  final String selectedExitId;
  final VoidCallback onOpenSelected;
  final String nativeAppKey;
  final StationExitNativeMapBuilder? nativeMapBuilder;

  @override
  State<StationExitMapPreview> createState() => _StationExitMapPreviewState();
}

class _StationExitMapPreviewState extends State<StationExitMapPreview>
    with WidgetsBindingObserver {
  KakaoMapController? _controller;
  final _pois = <String, Poi>{};
  bool _mapFailed = false;
  bool _appActive = true;
  bool _routeVisible = true;
  bool? _controllerRunning;
  int? _configuringGeneration;
  Future<void> _selectionStyleQueue = Future<void>.value();
  int _generation = 0;

  List<StationExitPreviewPoint> get _points => _previewPointsFor(widget);

  List<StationExitPreviewPoint> _previewPointsFor(
    StationExitMapPreview preview,
  ) {
    final points = stationExitPreviewPoints(preview.exits);
    final selectedExit = preview.exits.firstWhere(
      (exit) => exit.id == preview.selectedExitId,
    );
    if (selectedExit.hasCoordinate ||
        preview.station.latitude == null ||
        preview.station.longitude == null) {
      return points;
    }
    return [
      (
        id: selectedExit.id,
        number: selectedExit.exitNumber,
        latitude: preview.station.latitude!,
        longitude: preview.station.longitude!,
      ),
      ...points,
    ];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeVisible = TickerMode.valuesOf(context).enabled;
    if (_routeVisible != routeVisible) {
      _routeVisible = routeVisible;
      _syncControllerLifecycle();
    }
  }

  @override
  void didUpdateWidget(covariant StationExitMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPoints = _previewPointsFor(oldWidget);
    if (oldWidget.station.id != widget.station.id ||
        oldWidget.station.latitude != widget.station.latitude ||
        oldWidget.station.longitude != widget.station.longitude ||
        !listEquals(oldPoints, _points)) {
      _finishController();
      _pois.clear();
      _mapFailed = false;
      _generation++;
      return;
    }
    if (oldWidget.selectedExitId != widget.selectedExitId) {
      _scheduleSelectedPoiStyleSync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _controllerRunning = null;
    _syncControllerLifecycle();
  }

  @override
  Widget build(BuildContext context) {
    if (!canShowStationExitMapPreview(
      station: widget.station,
      exits: widget.exits,
    )) {
      return const SizedBox.shrink();
    }
    if (widget.nativeAppKey.trim().isEmpty) {
      return const _MapMessagePanel(
        message: '지도 미리보기를 사용할 수 없어요.',
        detail: '아래 카카오맵에서 보기 버튼은 계속 사용할 수 있어요.',
      );
    }
    if (_mapFailed) {
      return _MapMessagePanel(
        message: '지도 미리보기를 불러오지 못했어요.',
        detail: '네트워크 상태를 확인한 뒤 다시 시도해 주세요.',
        action: TextButton(onPressed: _retry, child: const Text('다시 시도')),
      );
    }

    final option = KakaoMapOption(position: _initialPosition, zoomLevel: 16);
    final builder = widget.nativeMapBuilder ?? _buildNativeMap;
    final mapGeneration = _generation;
    final selectedExit = widget.exits.firstWhere(
      (exit) => exit.id == widget.selectedExitId,
    );
    final selectedTarget = stationExitMapTarget(
      station: widget.station,
      exit: selectedExit,
    );

    return SizedBox(
      key: const Key('stationExitMapPreview'),
      height: 144,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: builder(
                key: ValueKey('stationExitNativeMap-$_generation'),
                option: option,
                onMapReady: (controller) {
                  if (mounted && mapGeneration == _generation) {
                    _onMapReady(controller);
                  }
                },
                onMapError: (error) {
                  if (mounted && mapGeneration == _generation) {
                    _onMapError(error);
                  }
                },
              ),
            ),
            if (selectedTarget != null)
              Semantics(
                button: true,
                label: selectedTarget.usesStationFallback
                    ? '${selectedExit.name} 카카오맵에서 보기, 출구 좌표가 없어 역 위치 기준으로 새 앱이 열립니다'
                    : '${widget.station.nameKo}역 ${selectedExit.name} 카카오맵에서 보기, 새 앱이 열립니다',
                onTap: widget.onOpenSelected,
                child: ExcludeSemantics(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onOpenSelected,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  LatLng get _initialPosition {
    final points = _points;
    if (points.isNotEmpty) {
      return LatLng(points.first.latitude, points.first.longitude);
    }
    return LatLng(widget.station.latitude!, widget.station.longitude!);
  }

  void _onMapReady(KakaoMapController controller) {
    _controller = controller;
    _controllerRunning = true;
    _syncControllerLifecycle();
    final generation = _generation;
    unawaited(_configureMap(controller, generation));
  }

  Future<void> _configureMap(
    KakaoMapController controller,
    int generation,
  ) async {
    final selectedExitIdAtStart = widget.selectedExitId;
    _configuringGeneration = generation;
    try {
      await Future.wait([
        for (final gesture in GestureType.values)
          if (gesture != GestureType.unknown)
            controller.setGesture(gesture, false),
      ]);
      await controller.labelLayer.setClickable(false);
      for (final point in _points) {
        if (!mounted || generation != _generation) {
          return;
        }
        final style = await _markerStyle(
          point.number,
          selected: point.id == selectedExitIdAtStart,
        );
        if (!mounted || generation != _generation) {
          return;
        }
        final poi = await controller.labelLayer.addPoi(
          LatLng(point.latitude, point.longitude),
          id: point.id,
          style: style,
        );
        if (!mounted || generation != _generation) {
          return;
        }
        _pois[point.id] = poi;
      }
      final positions = [
        for (final point in _points) LatLng(point.latitude, point.longitude),
      ];
      if (positions.length > 1) {
        await controller.moveCamera(
          CameraUpdate.fitMapPoints(positions, padding: 32),
        );
      } else {
        await controller.moveCamera(
          CameraUpdate.newCenterPosition(_initialPosition, zoomLevel: 16),
        );
      }
      if (selectedExitIdAtStart != widget.selectedExitId) {
        await _synchronizeSelectedPoiStyles(generation);
      }
    } on Object catch (error, stackTrace) {
      _reportSanitizedError(error, stackTrace, '카카오맵 미리보기 구성 실패');
      if (mounted && generation == _generation) {
        setState(() => _mapFailed = true);
      }
    } finally {
      if (_configuringGeneration == generation) {
        _configuringGeneration = null;
      }
    }
  }

  Future<void> _synchronizeSelectedPoiStyles(int generation) async {
    while (mounted && generation == _generation) {
      final selectedExitId = widget.selectedExitId;
      for (final point in _points) {
        final poi = _pois[point.id];
        if (poi != null) {
          await poi.changeStyles(
            await _markerStyle(
              point.number,
              selected: point.id == selectedExitId,
            ),
          );
        }
      }
      if (selectedExitId == widget.selectedExitId) {
        return;
      }
    }
  }

  Future<PoiStyle> _markerStyle(String number, {required bool selected}) async {
    final colorScheme = Theme.of(context).colorScheme;
    final size = selected ? 36.0 : 32.0;
    final image = await KImage.fromWidget(
      _ExitNumberMarker(
        number: number,
        selected: selected,
        primary: colorScheme.primary,
        onPrimary: colorScheme.onPrimary,
        surface: colorScheme.surface,
      ),
      Size.square(size),
      context: context,
    );
    return PoiStyle(icon: image, anchor: const KPoint(0.5, 0.5));
  }

  void _scheduleSelectedPoiStyleSync() {
    final generation = _generation;
    _selectionStyleQueue = _selectionStyleQueue.then((_) async {
      if (!mounted ||
          generation != _generation ||
          _configuringGeneration == generation) {
        return;
      }
      try {
        await _synchronizeSelectedPoiStyles(generation);
      } on Object catch (error, stackTrace) {
        _reportSanitizedError(error, stackTrace, '카카오맵 출구 선택 표시 실패');
      }
    });
  }

  void _onMapError(Error error) {
    _reportSanitizedError(error, StackTrace.current, '카카오맵 미리보기 렌더 오류');
    _finishController();
    if (mounted) {
      setState(() => _mapFailed = true);
    }
  }

  void _retry() {
    _finishController();
    _pois.clear();
    setState(() {
      _mapFailed = false;
      _generation++;
    });
  }

  void _runControllerAction(Future<void> Function() action, String context) {
    unawaited(
      action().onError((error, stackTrace) {
        _reportSanitizedError(
          error ?? StateError('Unknown Kakao map controller error'),
          stackTrace,
          context,
        );
      }),
    );
  }

  void _syncControllerLifecycle() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final shouldRun = _appActive && _routeVisible;
    if (_controllerRunning == shouldRun) {
      return;
    }
    _controllerRunning = shouldRun;
    _runControllerAction(
      shouldRun ? controller.resume : controller.pause,
      shouldRun ? '카카오맵 미리보기 resume 실패' : '카카오맵 미리보기 pause 실패',
    );
  }

  void _finishController() {
    final controller = _controller;
    _controller = null;
    _controllerRunning = null;
    if (controller != null) {
      _runControllerAction(controller.finish, '카카오맵 미리보기 종료 실패');
    }
  }

  void _reportSanitizedError(
    Object error,
    StackTrace stackTrace,
    String context,
  ) {
    reportMobileError(
      StateError('$context: ${error.runtimeType}'),
      stackTrace,
      context: context,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finishController();
    super.dispose();
  }
}

Widget _buildNativeMap({
  required Key key,
  required KakaoMapOption option,
  required ValueChanged<KakaoMapController> onMapReady,
  required ValueChanged<Error> onMapError,
}) {
  return KakaoMap(
    key: key,
    option: option,
    forceGesture: false,
    forceHybridComposition: false,
    onMapReady: onMapReady,
    onMapError: onMapError,
  );
}

class _ExitNumberMarker extends StatelessWidget {
  const _ExitNumberMarker({
    required this.number,
    required this.selected,
    required this.primary,
    required this.onPrimary,
    required this.surface,
  });

  final String number;
  final bool selected;
  final Color primary;
  final Color onPrimary;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? primary : surface,
        shape: BoxShape.circle,
        border: Border.all(color: primary, width: selected ? 3 : 2),
      ),
      child: Center(
        child: FittedBox(
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Text(
              number,
              style: TextStyle(
                color: selected ? onPrimary : primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapMessagePanel extends StatelessWidget {
  const _MapMessagePanel({
    required this.message,
    required this.detail,
    this.action,
  });

  final String message;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('stationExitMapPreview'),
      constraints: const BoxConstraints(minHeight: 144),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          ?action,
        ],
      ),
    );
  }
}
