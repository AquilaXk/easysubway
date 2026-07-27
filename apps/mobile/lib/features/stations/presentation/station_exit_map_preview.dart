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
  int _generation = 0;

  List<StationExitPreviewPoint> get _points =>
      stationExitPreviewPoints(widget.exits);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant StationExitMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPoints = stationExitPreviewPoints(oldWidget.exits);
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
      unawaited(
        _updateSelectedPoi(oldWidget.selectedExitId, widget.selectedExitId),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        _runControllerAction(controller.resume, '카카오맵 미리보기 resume 실패');
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        _runControllerAction(controller.pause, '카카오맵 미리보기 pause 실패');
    }
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

    final option = KakaoMapOption(
      position: _initialPosition,
      zoomLevel: 16,
      viewName: 'station-exit-${widget.station.id}-$_generation',
    );
    final builder = widget.nativeMapBuilder ?? _buildNativeMap;
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
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            builder(
              key: ValueKey('stationExitNativeMap-$_generation'),
              option: option,
              onMapReady: _onMapReady,
              onMapError: _onMapError,
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
    final generation = _generation;
    unawaited(_configureMap(controller, generation));
  }

  Future<void> _configureMap(
    KakaoMapController controller,
    int generation,
  ) async {
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
        _pois[point.id] = await controller.labelLayer.addPoi(
          LatLng(point.latitude, point.longitude),
          id: point.id,
          style: await _markerStyle(
            point.number,
            selected: point.id == widget.selectedExitId,
          ),
        );
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
    } on Object catch (error, stackTrace) {
      _reportSanitizedError(error, stackTrace, '카카오맵 미리보기 구성 실패');
      if (mounted && generation == _generation) {
        setState(() => _mapFailed = true);
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
      ),
      Size.square(size),
      context: context,
    );
    return PoiStyle(icon: image, anchor: const KPoint(0.5, 0.5));
  }

  Future<void> _updateSelectedPoi(String previousId, String selectedId) async {
    final previous = _pois[previousId];
    final selected = _pois[selectedId];
    final previousPoint = _points
        .where((point) => point.id == previousId)
        .firstOrNull;
    final selectedPoint = _points
        .where((point) => point.id == selectedId)
        .firstOrNull;
    try {
      if (previous != null && previousPoint != null) {
        await previous.changeStyles(
          await _markerStyle(previousPoint.number, selected: false),
        );
      }
      if (!mounted || widget.selectedExitId != selectedId) {
        return;
      }
      if (selected != null && selectedPoint != null) {
        await selected.changeStyles(
          await _markerStyle(selectedPoint.number, selected: true),
        );
      }
    } on Object catch (error, stackTrace) {
      _reportSanitizedError(error, stackTrace, '카카오맵 출구 선택 표시 실패');
    }
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

  void _finishController() {
    final controller = _controller;
    _controller = null;
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
  });

  final String number;
  final bool selected;
  final Color primary;
  final Color onPrimary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? primary : Colors.white,
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
                fontWeight: FontWeight.w800,
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
      height: 144,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
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
