import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'accessible_design.dart';
import 'features/network_map/domain/map_camera.dart';
import 'features/network_map/infrastructure/android_route_map_viewport_webview.dart';
import 'features/network_map/infrastructure/ios_route_map_viewport_webview.dart';
import 'features/network_map/infrastructure/route_map_renderer.dart';
import 'features/route_draft/application/route_draft_controller.dart';
import 'features/route_draft/domain/route_draft.dart';

abstract interface class NetworkMapRepository {
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId});
}

class NetworkMapData {
  const NetworkMapData({
    required this.regions,
    required this.selectedRegion,
    required this.lines,
    required this.stations,
    required this.edges,
    required this.positionSources,
    this.stationLineMemberships = const [],
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final List<NetworkMapLine> lines;
  final List<NetworkMapStation> stations;
  final List<NetworkMapEdge> edges;
  final List<NetworkMapPositionSource> positionSources;
  final List<NetworkMapStationLineMembership> stationLineMemberships;

  factory NetworkMapData.fromJson(Map<String, Object?> json) {
    return NetworkMapData(
      regions: _objectList(
        json['regions'],
      ).map(NetworkMapRegion.fromJson).toList(growable: false),
      selectedRegion: json['selectedRegion'] as String? ?? '',
      lines: _objectList(
        json['lines'],
      ).map(NetworkMapLine.fromJson).toList(growable: false),
      stations: _objectList(
        json['stations'],
      ).map(NetworkMapStation.fromJson).toList(growable: false),
      edges: _objectList(
        json['edges'],
      ).map(NetworkMapEdge.fromJson).toList(growable: false),
      positionSources: _objectList(
        json['positionSources'],
      ).map(NetworkMapPositionSource.fromJson).toList(growable: false),
      stationLineMemberships: _objectList(
        json['stationLineMemberships'],
      ).map(NetworkMapStationLineMembership.fromJson).toList(growable: false),
    );
  }
}

class NetworkMapStationLineMembership {
  const NetworkMapStationLineMembership({
    required this.stationId,
    required this.lineId,
  });

  final String stationId;
  final String lineId;

  factory NetworkMapStationLineMembership.fromJson(Map<String, Object?> json) {
    return NetworkMapStationLineMembership(
      stationId: json['stationId'] as String? ?? '',
      lineId: json['lineId'] as String? ?? '',
    );
  }
}

class NetworkMapRegion {
  const NetworkMapRegion({required this.name});

  final String name;
  String get displayName => _displayRegionName(name);

  factory NetworkMapRegion.fromJson(Map<String, Object?> json) {
    return NetworkMapRegion(name: json['name'] as String? ?? '');
  }
}

class NetworkMapLine {
  const NetworkMapLine({
    required this.id,
    required this.name,
    required this.color,
    required this.region,
  });

  final String id;
  final String name;
  final String color;
  final String region;

  factory NetworkMapLine.fromJson(Map<String, Object?> json) {
    return NetworkMapLine(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? json['nameKo'] as String? ?? '',
      color: json['color'] as String? ?? '#006D77',
      region: json['region'] as String? ?? '',
    );
  }

  String get shortName {
    final withoutRegion = name.replaceFirst('수도권 ', '');
    return withoutRegion.isEmpty ? name : withoutRegion;
  }

  String get badgeText {
    final label = shortName.replaceAll('호선', '');
    final numberMatch = RegExp(r'(\d+)').firstMatch(label);
    if (numberMatch != null) {
      return numberMatch.group(1)!;
    }
    if (label.contains('GTX-A')) {
      return 'A';
    }
    final compact = label
        .replaceAll('부산김해경전철', '김해')
        .replaceAll('김포골드라인', '김포')
        .replaceAll('경의중앙', '경의')
        .replaceAll('수인분당', '수인')
        .replaceAll('우이신설', '우이')
        .replaceAll('신분당', '신분')
        .replaceAll('에버라인', '에버')
        .replaceAll('자기부상', '자기')
        .replaceAll('의정부', '의정');
    return compact.characters.take(2).toString();
  }
}

class NetworkMapStation {
  const NetworkMapStation({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    required this.region,
    required this.lineId,
    required this.stationCode,
    required this.sequence,
    required this.position,
  });

  final String id;
  final String nameKo;
  final String nameEn;
  final String region;
  final String lineId;
  final String stationCode;
  final int sequence;
  final NetworkMapPosition position;

  String get displayName => nameKo.endsWith('역') ? nameKo : '$nameKo역';

  factory NetworkMapStation.fromJson(Map<String, Object?> json) {
    return NetworkMapStation(
      id: json['id'] as String? ?? '',
      nameKo: json['nameKo'] as String? ?? '',
      nameEn: json['nameEn'] as String? ?? '',
      region: json['region'] as String? ?? '',
      lineId: json['lineId'] as String? ?? '',
      stationCode: json['stationCode'] as String? ?? '',
      sequence: json['sequence'] as int? ?? 0,
      position: NetworkMapPosition.fromJson(
        (json['position'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
    );
  }
}

class NetworkMapPosition {
  const NetworkMapPosition({
    required this.x,
    required this.y,
    required this.labelDx,
    required this.labelDy,
    required this.upPath,
    required this.downPath,
    required this.sourceId,
    this.labelPolygon = '',
  });

  final int x;
  final int y;
  final int labelDx;
  final int labelDy;
  final String labelPolygon;
  final String upPath;
  final String downPath;
  final String sourceId;

  factory NetworkMapPosition.fromJson(Map<String, Object?> json) {
    return NetworkMapPosition(
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
      labelDx: json['labelDx'] as int? ?? 0,
      labelDy: json['labelDy'] as int? ?? 0,
      labelPolygon: json['labelPolygon'] as String? ?? '',
      upPath: json['upPath'] as String? ?? '',
      downPath: json['downPath'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? '',
    );
  }
}

class NetworkMapEdge {
  const NetworkMapEdge({
    required this.id,
    required this.lineId,
    required this.fromStationId,
    required this.toStationId,
    required this.accessibilityStatus,
    required this.reliabilityScore,
  });

  final String id;
  final String lineId;
  final String fromStationId;
  final String toStationId;
  final String accessibilityStatus;
  final int reliabilityScore;

  factory NetworkMapEdge.fromJson(Map<String, Object?> json) {
    return NetworkMapEdge(
      id: json['id'] as String? ?? '',
      lineId: json['lineId'] as String? ?? '',
      fromStationId: json['fromStationId'] as String? ?? '',
      toStationId: json['toStationId'] as String? ?? '',
      accessibilityStatus: json['accessibilityStatus'] as String? ?? 'UNKNOWN',
      reliabilityScore: json['reliabilityScore'] as int? ?? 0,
    );
  }
}

class NetworkMapPositionSource {
  const NetworkMapPositionSource({
    required this.id,
    required this.name,
    required this.licenseStatus,
  });

  final String id;
  final String name;
  final String licenseStatus;

  factory NetworkMapPositionSource.fromJson(Map<String, Object?> json) {
    return NetworkMapPositionSource(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      licenseStatus: json['licenseStatus'] as String? ?? '',
    );
  }
}

class NetworkMapScreen extends StatefulWidget {
  const NetworkMapScreen({
    required this.repository,
    required this.routeDraftController,
    required this.onOpenRouteSearch,
    required this.onOpenStationSearch,
    required this.onOpenSaved,
    required this.onOpenSettings,
    super.key,
  });

  final NetworkMapRepository repository;
  final RouteDraftController routeDraftController;
  final Future<void> Function() onOpenRouteSearch;
  final VoidCallback onOpenStationSearch;
  final VoidCallback onOpenSaved;
  final VoidCallback onOpenSettings;

  @override
  State<NetworkMapScreen> createState() => _NetworkMapScreenState();
}

class _NetworkMapScreenState extends State<NetworkMapScreen> {
  String? _selectedRegion;
  late Future<NetworkMapData> _future = _loadMap();

  Future<NetworkMapData> _loadMap() {
    return widget.repository.getNetworkMap(region: _selectedRegion);
  }

  void _reload({String? region}) {
    setState(() {
      _selectedRegion = region ?? _selectedRegion;
      _future = _loadMap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('networkMapScreen'),
      appBar: AppBar(
        title: const Text('노선도'),
        actions: [
          IconButton(
            key: const Key('networkMapSearchButton'),
            tooltip: '역 검색',
            onPressed: widget.onOpenStationSearch,
            icon: const Icon(Icons.search),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<NetworkMapData>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snapshot.data!;
            return Stack(
              children: [
                Positioned.fill(
                  child: _NetworkMapCanvas(
                    data: data,
                    onStationTap: _showStationSheet,
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _RegionTabs(
                        regions: data.regions,
                        selectedRegion: data.selectedRegion,
                        onSelected: (region) => _reload(region: region),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        height: 72,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              Navigator.of(context).maybePop();
              break;
            case 1:
              break;
            case 2:
              Navigator.of(context).maybePop();
              widget.onOpenRouteSearch();
              break;
            case 3:
              Navigator.of(context).maybePop();
              widget.onOpenSaved();
              break;
            case 4:
              Navigator.of(context).maybePop();
              widget.onOpenSettings();
              break;
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '홈'),
          NavigationDestination(icon: Icon(Icons.map), label: '노선도'),
          NavigationDestination(icon: Icon(Icons.route_outlined), label: '길찾기'),
          NavigationDestination(icon: Icon(Icons.star_border), label: '즐겨찾기'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: '더보기'),
        ],
      ),
    );
  }

  void _showStationSheet(
    NetworkMapStation station,
    List<NetworkMapLine> lines,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _StationSheet(
          station: station,
          lines: lines,
          onSetOrigin: () {
            widget.routeDraftController.setOrigin(
              RouteDraftStation(id: station.id, nameKo: station.nameKo),
            );
            Navigator.of(context).pop();
          },
          onSetDestination: () {
            widget.routeDraftController.setDestination(
              RouteDraftStation(id: station.id, nameKo: station.nameKo),
            );
            Navigator.of(context).pop();
          },
          onOpenRouteSearch: () {
            Navigator.of(context).pop();
            widget.onOpenRouteSearch();
          },
        );
      },
    );
  }
}

class _RegionTabs extends StatelessWidget {
  const _RegionTabs({
    required this.regions,
    required this.selectedRegion,
    required this.onSelected,
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final visibleRegions = regions.isEmpty
        ? const [NetworkMapRegion(name: '수도권')]
        : regions;
    final selected =
        visibleRegions.any((region) => region.name == selectedRegion)
        ? selectedRegion
        : visibleRegions.first.name;
    return SizedBox(
      key: const Key('mapRegionTabs'),
      width: 108,
      height: EasySubwayTouchTarget.general,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        initialValue: selected,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final region in visibleRegions)
            PopupMenuItem<String>(
              value: region.name,
              child: Text(region.displayName),
            ),
        ],
        child: _RegionMenuButton(
          label: _displayRegionName(selected),
          semanticLabel: '지역: ${_displayRegionName(selected)}',
        ),
      ),
    );
  }
}

class _RegionMenuButton extends StatelessWidget {
  const _RegionMenuButton({required this.label, required this.semanticLabel});

  final String label;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          height: EasySubwayTouchTarget.general,
          padding: const EdgeInsets.only(left: 10, right: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD7E1E3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF102A2C),
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_drop_down,
                size: 22,
                color: Color(0xFF4C5759),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationLineChip extends StatelessWidget {
  const _StationLineChip({required this.line});

  final NetworkMapLine line;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: line.shortName,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFB),
          border: Border.all(color: const Color(0xFFD7E2E4)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LineCircleBadge(line: line, size: 34),
            const SizedBox(width: 8),
            Text(
              line.shortName,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineCircleBadge extends StatelessWidget {
  const _LineCircleBadge({required this.line, required this.size});

  final NetworkMapLine line;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(line.color);
    final foreground =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : const Color(0xFF102A2D);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(
          line.badgeText,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: foreground,
            fontSize: RegExp(r'^\d+$').hasMatch(line.badgeText)
                ? size * 0.55
                : size * 0.32,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _RouteMapAsset {
  const _RouteMapAsset({
    required this.path,
    required this.mimeType,
    required this.width,
    required this.height,
    required this.coordinateWidth,
    required this.coordinateHeight,
  });

  final String path;
  final String mimeType;
  final double width;
  final double height;
  final double coordinateWidth;
  final double coordinateHeight;
}

_RouteMapAsset? _routeMapAssetForRegion(String region) {
  return switch (_displayRegionName(region)) {
    '수도권' => const _RouteMapAsset(
      path: 'assets/datapacks/maps/seoul-official-route-map.svg',
      mimeType: 'image/svg+xml',
      width: 5724,
      height: 6516,
      coordinateWidth: 5724,
      coordinateHeight: 6516,
    ),
    '부산' => const _RouteMapAsset(
      path: 'assets/datapacks/maps/busan-official-route-map.svg',
      mimeType: 'image/svg+xml',
      width: 3704,
      height: 1134,
      coordinateWidth: 3703.9,
      coordinateHeight: 1133.9,
    ),
    '광주' => const _RouteMapAsset(
      path: 'assets/datapacks/maps/gwangju-cc-by-sa-route-map.svg',
      mimeType: 'image/svg+xml',
      width: 720,
      height: 600,
      coordinateWidth: 190.50001,
      coordinateHeight: 158.75,
    ),
    '대구' => const _RouteMapAsset(
      path: 'assets/datapacks/maps/daegu-official-route-map.svg',
      mimeType: 'image/svg+xml',
      width: 5348,
      height: 862,
      coordinateWidth: 5348,
      coordinateHeight: 861.73,
    ),
    '대전' => const _RouteMapAsset(
      path: 'assets/datapacks/maps/daejeon-official-route-map.svg',
      mimeType: 'image/svg+xml',
      width: 853,
      height: 813,
      coordinateWidth: 853.33,
      coordinateHeight: 813.33,
    ),
    _ => null,
  };
}

class _NetworkMapCanvas extends StatefulWidget {
  const _NetworkMapCanvas({required this.data, required this.onStationTap});

  final NetworkMapData data;
  final void Function(NetworkMapStation station, List<NetworkMapLine> lines)
  onStationTap;

  @override
  State<_NetworkMapCanvas> createState() => _NetworkMapCanvasState();
}

const _minMapScale = 0.08;
const _maxMapScale = 4.8;
const _routeMapGestureRendererCommitInterval = Duration(milliseconds: 700);
const _routeMapGestureMaxTranslationDriftFraction = 0.85;
const _routeMapGestureMaxScaleRatio = 2.4;
const _routeMapGestureRendererOverscanFactor = 3.25;

class _NetworkMapCanvasState extends State<_NetworkMapCanvas>
    with WidgetsBindingObserver {
  String? _layoutKey;
  MapCameraState? _camera;
  MapCameraState? _pendingCamera;
  MapCameraState? _requestedRendererCamera;
  MapCameraState? _presentedRendererCamera;
  final _requestedRendererCamerasByRevision = <int, MapCameraState>{};
  bool _routeMapRendererActive = false;
  DateTime? _lastRendererCameraRequestAt;
  bool _cameraFrameCallbackScheduled = false;
  bool _forceRendererCameraCommit = false;
  bool _gestureActive = false;
  MapCameraState? _gestureStartCamera;
  Offset? _gestureStartFocalPoint;
  RouteMapRendererHealthMonitor? _rendererMonitor;
  RouteMapRendererController? _rendererController;
  String? _geometryCacheKey;
  _MapGeometry? _geometryCache;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingCamera = null;
    _requestedRendererCamera = null;
    _presentedRendererCamera = null;
    _requestedRendererCamerasByRevision.clear();
    _releaseRenderer(disposeRenderer: true);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive || AppLifecycleState.paused:
        _ignoreRendererLifecycleFailure(_rendererMonitor?.trimMemory());
      case AppLifecycleState.detached:
        _releaseRenderer(disposeRenderer: true);
      case AppLifecycleState.resumed || AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void didHaveMemoryPressure() {
    _ignoreRendererLifecycleFailure(_rendererMonitor?.trimMemory());
  }

  void _ignoreRendererLifecycleFailure(Future<void>? future) {
    if (future == null) {
      return;
    }
    unawaited(future.catchError((Object _) {}));
  }

  void _releaseRenderer({required bool disposeRenderer}) {
    final monitor = _rendererMonitor;
    _rendererController = null;
    if (monitor == null) {
      return;
    }
    if (!disposeRenderer) {
      _rendererMonitor = null;
    }
    _ignoreRendererLifecycleFailure(
      monitor.close(disposeRenderer: disposeRenderer).whenComplete(() {
        if (identical(_rendererMonitor, monitor)) {
          _rendererMonitor = null;
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stationLinesById = _stationLinesById(widget.data);
    final mapAsset = _routeMapAssetForRegion(widget.data.selectedRegion);
    return Container(
      key: const Key('networkMapSurface'),
      decoration: const BoxDecoration(color: Colors.white),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = _geometryFor(mapAsset, widget.data);
          final fullBounds = Rect.fromLTWH(
            0,
            0,
            geometry.width,
            geometry.height,
          );
          final minScale = _minimumMapScaleForBounds(fullBounds, constraints);
          final routeMapRendererActive =
              mapAsset != null &&
              defaultTargetPlatform != TargetPlatform.android;
          final layoutKey =
              '${widget.data.selectedRegion}:${geometry.width}:${geometry.height}:${constraints.maxWidth}:${constraints.maxHeight}:$routeMapRendererActive';
          if (_layoutKey != layoutKey) {
            _layoutKey = layoutKey;
            _pendingCamera = null;
            _requestedRendererCamera = null;
            _presentedRendererCamera = null;
            _requestedRendererCamerasByRevision.clear();
            _routeMapRendererActive = routeMapRendererActive;
            _lastRendererCameraRequestAt = null;
            _gestureActive = false;
            final initialCamera = _cameraForBounds(
              geometry.initialBounds,
              constraints,
              sourceBounds: fullBounds,
              minScale: minScale,
            );
            final initialRendererCamera = networkMapOverscannedRendererCamera(
              initialCamera,
            );
            _camera = initialCamera;
            if (routeMapRendererActive) {
              _requestedRendererCamera = initialRendererCamera;
              _presentedRendererCamera = initialRendererCamera;
            }
          }
          final camera =
              _camera ??
              _cameraForBounds(
                geometry.initialBounds,
                constraints,
                sourceBounds: fullBounds,
                minScale: minScale,
              );
          return Stack(
            children: [
              Positioned.fill(
                child: mapAsset == null
                    ? const _OriginalRouteMapUnavailable()
                    : defaultTargetPlatform == TargetPlatform.android
                    ? _AndroidRouteMapFallbackLayer(
                        data: widget.data,
                        geometry: geometry,
                        camera: camera,
                      )
                    : _RouteMapViewportRenderer(
                        asset: mapAsset,
                        camera:
                            _requestedRendererCamera ??
                            networkMapOverscannedRendererCamera(camera),
                        presentedCamera:
                            _presentedRendererCamera ??
                            _requestedRendererCamera ??
                            networkMapOverscannedRendererCamera(camera),
                        visualCamera: camera,
                        onControllerCreated: _attachRendererController,
                      ),
              ),
              Positioned.fill(
                child: Listener(
                  onPointerCancel: (_) => _endScaleGesture(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onScaleStart: (details) {
                      if (!_gestureActive) {
                        setState(() {
                          _gestureActive = true;
                        });
                      }
                      _gestureStartCamera = camera;
                      _gestureStartFocalPoint = details.localFocalPoint;
                    },
                    onScaleUpdate: (details) {
                      _updateCameraForGesture(details);
                    },
                    onScaleEnd: (_) {
                      _endScaleGesture();
                    },
                    onTapUp: (details) {
                      _openNearestStation(
                        details.localPosition,
                        stationLinesById,
                        geometry,
                        camera,
                      );
                    },
                  ),
                ),
              ),
              if (!_gestureActive)
                for (final station in _visibleCanonicalStations(
                  geometry: geometry,
                  camera: camera,
                ))
                  Positioned.fromRect(
                    rect: _sourceRectToViewport(
                      _stationHitRect(
                        station,
                        geometry,
                        nodeRadius: 24 / camera.scale,
                        labelHeight: 40 / camera.scale,
                      ),
                      camera,
                    ),
                    child: _StationHitTarget(
                      key: Key(
                        'networkMapStation-${station.id.replaceFirst('station-', '')}-${station.lineId}',
                      ),
                      station: station,
                      onTap: () => widget.onStationTap(
                        station,
                        stationLinesById[station.id] ?? const [],
                      ),
                    ),
                  ),
              Positioned(
                right: 14,
                top: 12,
                child: _MapControls(
                  onZoomIn: () => _scaleMap(1.25),
                  onZoomOut: () => _scaleMap(0.8),
                  onOverview: () {
                    _setCamera(
                      _cameraForBounds(
                        fullBounds,
                        constraints,
                        sourceBounds: fullBounds,
                        contain: true,
                        minScale: minScale,
                        revision: camera.revision + 1,
                      ),
                    );
                  },
                  onCenter: () {
                    _setCamera(
                      _cameraForBounds(
                        _readableBoundsFor(geometry),
                        constraints,
                        sourceBounds: fullBounds,
                        minScale: minScale,
                        revision: camera.revision + 1,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _scaleMap(double factor) {
    final camera = _pendingCamera ?? _camera;
    if (camera == null || camera.viewportSize == Size.zero) {
      return;
    }
    _setCamera(
      camera
          .zoomBy(factor, focalPoint: camera.viewportSize.center(Offset.zero))
          .clamped(viewportMargin: 220),
    );
  }

  _MapGeometry _geometryFor(_RouteMapAsset? mapAsset, NetworkMapData data) {
    final assetKey = mapAsset == null
        ? 'generated'
        : '${mapAsset.path}:${mapAsset.coordinateWidth}:${mapAsset.coordinateHeight}';
    final cacheKey =
        '$assetKey:${data.selectedRegion}:${identityHashCode(data.stations)}:${data.stations.length}';
    final cached = _geometryCache;
    if (_geometryCacheKey == cacheKey && cached != null) {
      return cached;
    }
    final geometry = mapAsset == null
        ? _MapGeometry.fromStations(data.stations)
        : _MapGeometry.fromOriginalAsset(mapAsset, data.stations);
    _geometryCacheKey = cacheKey;
    _geometryCache = geometry;
    return geometry;
  }

  void _updateCameraForGesture(ScaleUpdateDetails details) {
    final startCamera = _gestureStartCamera;
    final startFocalPoint = _gestureStartFocalPoint;
    if (startCamera == null || startFocalPoint == null) {
      return;
    }
    final viewportCenter = startCamera.viewportSize.center(Offset.zero);
    final sourceBefore = startCamera.viewportToSourcePoint(startFocalPoint);
    final nextScale = (startCamera.scale * details.scale)
        .clamp(startCamera.minScale, startCamera.maxScale)
        .toDouble();
    final nextCenter =
        sourceBefore - (details.localFocalPoint - viewportCenter) / nextScale;
    _setCamera(
      startCamera
          .copyWith(
            center: nextCenter,
            scale: nextScale,
            revision: startCamera.revision + 1,
          )
          .clamped(viewportMargin: 220),
    );
  }

  void _endScaleGesture() {
    _forceRendererCameraCommit = true;
    if (_pendingCamera == null && _camera != null) {
      _pendingCamera = _camera;
    }
    _scheduleCameraCommit();
    _gestureStartCamera = null;
    _gestureStartFocalPoint = null;
    if (!_gestureActive) {
      return;
    }
    if (!mounted) {
      _gestureActive = false;
      return;
    }
    setState(() {
      _gestureActive = false;
    });
  }

  void _setCamera(MapCameraState camera) {
    final currentCamera = _pendingCamera ?? _camera;
    final nextCamera = currentCamera == null
        ? camera
        : networkMapCameraWithMonotonicRevision(
            current: currentCamera,
            next: camera,
          );
    if (identical(_pendingCamera, nextCamera) ||
        (_pendingCamera == null && identical(_camera, nextCamera))) {
      return;
    }
    _pendingCamera = nextCamera;
    _scheduleCameraCommit();
  }

  void _scheduleCameraCommit() {
    if (_pendingCamera == null) {
      return;
    }
    if (_cameraFrameCallbackScheduled) {
      return;
    }
    _cameraFrameCallbackScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback((_) {
      _cameraFrameCallbackScheduled = false;
      final pendingCamera = _pendingCamera;
      final forceRendererCameraCommit = _forceRendererCameraCommit;
      _pendingCamera = null;
      _forceRendererCameraCommit = false;
      if (!mounted || pendingCamera == null) {
        return;
      }
      if (!_routeMapRendererActive) {
        setState(() {
          _camera = pendingCamera;
          _requestedRendererCamera = null;
          _presentedRendererCamera = null;
          _requestedRendererCamerasByRevision.clear();
        });
        return;
      }
      final rendererCamera = _requestedRendererCameraFor(
        pendingCamera,
        forceCommit: forceRendererCameraCommit,
      );
      if (identical(_camera, pendingCamera) &&
          identical(_requestedRendererCamera, rendererCamera)) {
        return;
      }
      setState(() {
        _camera = pendingCamera;
        if (!identical(_requestedRendererCamera, rendererCamera)) {
          _requestedRendererCamerasByRevision[rendererCamera.revision] =
              rendererCamera;
        }
        _requestedRendererCamera = rendererCamera;
      });
    });
  }

  MapCameraState _requestedRendererCameraFor(
    MapCameraState pendingCamera, {
    required bool forceCommit,
  }) {
    final committedCamera = networkMapRendererCommitBasisCamera(
      presentedCamera: _presentedRendererCamera,
      requestedCamera: _requestedRendererCamera,
      visualCamera: pendingCamera,
    );
    final requestedCamera = networkMapOverscannedRendererCamera(pendingCamera);
    final now = DateTime.now();
    final shouldCommit =
        forceCommit ||
        !_gestureActive ||
        committedCamera == null ||
        !networkMapRendererCameraCoversVisual(
          rendererCamera: committedCamera,
          visualCamera: pendingCamera,
        ) ||
        networkMapShouldCommitRendererCamera(
          committed: committedCamera,
          candidate: requestedCamera,
          elapsedSinceLastCommit: _lastRendererCameraRequestAt == null
              ? _routeMapGestureRendererCommitInterval
              : now.difference(_lastRendererCameraRequestAt!),
        );
    if (!shouldCommit) {
      final skippedCommitCamera = networkMapRendererCameraForSkippedCommit(
        requestedCamera: _requestedRendererCamera,
        candidateCamera: requestedCamera,
        visualCamera: pendingCamera,
      );
      if (!identical(skippedCommitCamera, _requestedRendererCamera)) {
        _lastRendererCameraRequestAt = now;
      }
      return skippedCommitCamera;
    }
    _lastRendererCameraRequestAt = now;
    return requestedCamera;
  }

  void _openNearestStation(
    Offset viewportPosition,
    Map<String, List<NetworkMapLine>> stationLinesById,
    _MapGeometry geometry,
    MapCameraState camera,
  ) {
    final station = _stationAtViewportPosition(
      viewportPosition,
      geometry,
      camera: camera,
    );
    if (station == null) {
      return;
    }
    widget.onStationTap(station, stationLinesById[station.id] ?? const []);
  }

  void _attachRendererController(RouteMapRendererController controller) {
    if (identical(_rendererController, controller)) {
      return;
    }
    _releaseRenderer(disposeRenderer: true);
    _rendererController = controller;
    late final RouteMapRendererHealthMonitor monitor;
    monitor = RouteMapRendererHealthMonitor(
      controller,
      onEvent: (event) => _handleRendererEvent(monitor, event),
    );
    _rendererMonitor = monitor;
    monitor.start();
  }

  void _handleRendererEvent(
    RouteMapRendererHealthMonitor monitor,
    RouteMapRendererEvent event,
  ) {
    final isCurrentMonitor = identical(_rendererMonitor, monitor);
    if (event is RouteMapRendererDisposed && isCurrentMonitor) {
      _rendererMonitor = null;
      _rendererController = null;
    }
    if (!isCurrentMonitor) {
      return;
    }
    if (event is RouteMapRendererFramePresented) {
      _markRendererFramePresented(event.revision);
    }
    if (!kDebugMode && !kProfileMode) {
      return;
    }
    switch (event) {
      case RouteMapRendererCameraLatency(:final revision, :final elapsed):
        debugPrint(
          'routeMapRenderer cameraLatency revision=$revision elapsedMs=${elapsed.inMilliseconds}',
        );
      case RouteMapRendererFrameTimeout(:final revision):
        debugPrint('routeMapRenderer frameTimeout revision=$revision');
      case RouteMapRendererRecovering(:final attempt):
        debugPrint('routeMapRenderer recovering attempt=$attempt');
      case RouteMapRendererProcessGone(:final didCrash):
        debugPrint('routeMapRenderer processGone didCrash=$didCrash');
      case RouteMapRendererMemoryTrimmed():
        debugPrint('routeMapRenderer memoryTrimmed');
      case RouteMapRendererDisposed():
        debugPrint('routeMapRenderer disposed');
      case RouteMapRendererCreated() ||
          RouteMapRendererAssetLoading() ||
          RouteMapRendererAssetReady() ||
          RouteMapRendererCameraRequested() ||
          RouteMapRendererFramePresented() ||
          RouteMapRendererFailed():
        break;
    }
  }

  void _markRendererFramePresented(int revision) {
    if (!networkMapShouldAcceptPresentedRendererRevision(
      revision: revision,
      presentedCamera: _presentedRendererCamera,
      requestedCamera: _requestedRendererCamera,
    )) {
      _requestedRendererCamerasByRevision.remove(revision);
      return;
    }
    final camera =
        _requestedRendererCamerasByRevision.remove(revision) ??
        (_requestedRendererCamera?.revision == revision
            ? _requestedRendererCamera
            : null);
    if (camera == null || identical(_presentedRendererCamera, camera)) {
      return;
    }
    if (!mounted) {
      _presentedRendererCamera = camera;
      return;
    }
    setState(() {
      _presentedRendererCamera = camera;
    });
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onOverview,
    required this.onCenter,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onOverview;
  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MapControlButton(
          key: const Key('networkMapZoomInButton'),
          tooltip: '확대',
          icon: Icons.add,
          onPressed: onZoomIn,
        ),
        const SizedBox(height: 8),
        _MapControlButton(
          key: const Key('networkMapZoomOutButton'),
          tooltip: '축소',
          icon: Icons.remove,
          onPressed: onZoomOut,
        ),
        const SizedBox(height: 8),
        _MapControlButton(
          key: const Key('networkMapOverviewButton'),
          tooltip: '지도 전체 보기',
          icon: Icons.fit_screen,
          onPressed: onOverview,
        ),
        const SizedBox(height: 8),
        _MapControlButton(
          key: const Key('networkMapLocateButton'),
          tooltip: '처음 위치로',
          icon: Icons.center_focus_strong,
          onPressed: onCenter,
        ),
      ],
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(8),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _AndroidRouteMapFallbackLayer extends StatelessWidget {
  const _AndroidRouteMapFallbackLayer({
    required this.data,
    required this.geometry,
    required this.camera,
  });

  final NetworkMapData data;
  final _MapGeometry geometry;
  final MapCameraState camera;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('routeMapViewportRenderer'),
      child: CustomPaint(
        painter: _AndroidRouteMapFallbackPainter(
          data: data,
          geometry: geometry,
          camera: camera,
          textScaler: MediaQuery.textScalerOf(context),
        ),
      ),
    );
  }
}

class _AndroidRouteMapFallbackPainter extends CustomPainter {
  const _AndroidRouteMapFallbackPainter({
    required this.data,
    required this.geometry,
    required this.camera,
    required this.textScaler,
  });

  final NetworkMapData data;
  final _MapGeometry geometry;
  final MapCameraState camera;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final lineById = {for (final line in data.lines) line.id: line};
    final stationsById = <String, List<NetworkMapStation>>{};
    final stationByLineKey = <String, NetworkMapStation>{};
    for (final station in data.stations) {
      stationsById.putIfAbsent(station.id, () => []).add(station);
      stationByLineKey[_networkMapStationLineKey(station.id, station.lineId)] =
          station;
    }
    final visibleStations = _visibleCanonicalStations(
      geometry: geometry,
      camera: camera,
    );
    final visibleRect = camera.visibleSourceRect.inflate(180 / camera.scale);
    final paintedSegments = <String>{};

    canvas.save();
    canvas.transform(camera.sourceToViewport.storage);

    for (final edge in data.edges) {
      final fromStation = _stationForMapEdgeEndpoint(
        edge.fromStationId,
        edge.lineId,
        stationByLineKey,
        stationsById,
      );
      final toStation = _stationForMapEdgeEndpoint(
        edge.toStationId,
        edge.lineId,
        stationByLineKey,
        stationsById,
      );
      if (fromStation == null || toStation == null) {
        continue;
      }
      final from = Offset(geometry.x(fromStation), geometry.y(fromStation));
      final to = Offset(geometry.x(toStation), geometry.y(toStation));
      if (!Rect.fromPoints(from, to).inflate(24).overlaps(visibleRect)) {
        continue;
      }
      final line = lineById[edge.lineId];
      final paint = Paint()
        ..color = line == null
            ? EasySubwayAccessibleColors.line
            : _colorFromHex(line.color)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 7 / camera.scale;
      canvas.drawLine(from, to, paint);
    }

    for (final station in data.stations) {
      if (!_stationHitRect(station, geometry).overlaps(visibleRect)) {
        continue;
      }
      final line = lineById[station.lineId];
      final color = line == null
          ? EasySubwayAccessibleColors.line
          : _colorFromHex(line.color);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 7 / camera.scale;
      for (final pathData in [
        station.position.upPath,
        station.position.downPath,
      ]) {
        if (pathData.isEmpty ||
            !paintedSegments.add('${station.lineId}:$pathData')) {
          continue;
        }
        final cachedPath = _cachedRouteMapPath(pathData, geometry.origin);
        if (cachedPath.bounds.overlaps(visibleRect)) {
          canvas.drawPath(cachedPath.path, paint);
        }
      }
    }

    final nodeStroke = Paint()
      ..color = const Color(0xFF2F3E42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / camera.scale;
    final nodeFill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    for (final station in visibleStations) {
      final center = Offset(geometry.x(station), geometry.y(station));
      final nodeRadius = 5 / camera.scale;
      canvas.drawCircle(center, nodeRadius, nodeFill);
      canvas.drawCircle(center, nodeRadius, nodeStroke);
    }
    canvas.restore();

    final labelStyle = const TextStyle(
      color: Color(0xFF102A2C),
      fontSize: 16,
      fontWeight: FontWeight.w800,
    );
    final labelBackground = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..style = PaintingStyle.fill;
    final occupiedLabels = <Rect>[];
    for (final station in visibleStations) {
      final center = Offset(geometry.x(station), geometry.y(station));
      final labelOffset = _labelOffsetFor(station);
      final labelPainter = TextPainter(
        text: TextSpan(text: station.nameKo, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final labelTopLeft = camera.sourceToViewportPoint(center + labelOffset);
      final labelRect = labelTopLeft & labelPainter.size;
      final paddedRect = labelRect.inflate(3);
      if (occupiedLabels.any((existing) => existing.overlaps(paddedRect))) {
        continue;
      }
      occupiedLabels.add(paddedRect);
      canvas.drawRRect(
        RRect.fromRectAndRadius(paddedRect, const Radius.circular(3)),
        labelBackground,
      );
      labelPainter.paint(canvas, labelTopLeft);
    }
  }

  @override
  bool shouldRepaint(covariant _AndroidRouteMapFallbackPainter oldDelegate) {
    return !_sameNetworkMapData(oldDelegate.data, data) ||
        !_sameMapGeometry(oldDelegate.geometry, geometry) ||
        !_sameMapCamera(oldDelegate.camera, camera) ||
        oldDelegate.textScaler != textScaler;
  }
}

String _networkMapStationLineKey(String stationId, String lineId) =>
    '$stationId:$lineId';

@visibleForTesting
NetworkMapStation? networkMapStationForMapEdgeEndpoint({
  required String endpoint,
  required String lineId,
  required Iterable<NetworkMapStation> stations,
}) {
  final stationsById = <String, List<NetworkMapStation>>{};
  final stationByLineKey = <String, NetworkMapStation>{};
  for (final station in stations) {
    stationsById.putIfAbsent(station.id, () => []).add(station);
    stationByLineKey[_networkMapStationLineKey(station.id, station.lineId)] =
        station;
  }
  return _stationForMapEdgeEndpoint(
    endpoint,
    lineId,
    stationByLineKey,
    stationsById,
  );
}

NetworkMapStation? _stationForMapEdgeEndpoint(
  String endpoint,
  String lineId,
  Map<String, NetworkMapStation> stationByLineKey,
  Map<String, List<NetworkMapStation>> stationsById,
) {
  final endpointStations = stationsById[endpoint];
  return stationByLineKey[endpoint] ??
      stationByLineKey[_networkMapStationLineKey(endpoint, lineId)] ??
      (endpointStations == null || endpointStations.isEmpty
          ? null
          : endpointStations.first);
}

class _CachedRouteMapPath {
  const _CachedRouteMapPath(this.path, this.bounds);

  final Path path;
  final Rect bounds;
}

final _routeMapPathCache = <String, _CachedRouteMapPath>{};

_CachedRouteMapPath _cachedRouteMapPath(String pathData, Offset origin) {
  final key = '${origin.dx}:${origin.dy}:$pathData';
  return _routeMapPathCache.putIfAbsent(key, () {
    final path = _pathFromSvg(pathData).shift(-origin);
    return _CachedRouteMapPath(path, path.getBounds());
  });
}

bool _sameMapCamera(MapCameraState a, MapCameraState b) {
  return a.sourceBounds == b.sourceBounds &&
      a.viewportSize == b.viewportSize &&
      a.center == b.center &&
      a.scale == b.scale &&
      a.minScale == b.minScale &&
      a.maxScale == b.maxScale &&
      a.revision == b.revision;
}

bool _sameMapGeometry(_MapGeometry a, _MapGeometry b) {
  return a.origin == b.origin &&
      a.focus == b.focus &&
      a.width == b.width &&
      a.height == b.height &&
      a.initialBounds == b.initialBounds &&
      a.overlayStyleScale == b.overlayStyleScale;
}

bool _sameNetworkMapData(NetworkMapData a, NetworkMapData b) {
  return a.selectedRegion == b.selectedRegion &&
      _sameNetworkMapLines(a.lines, b.lines) &&
      _sameNetworkMapStations(a.stations, b.stations) &&
      _sameNetworkMapEdges(a.edges, b.edges);
}

bool _sameNetworkMapLines(List<NetworkMapLine> a, List<NetworkMapLine> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    final left = a[index];
    final right = b[index];
    if (left.id != right.id ||
        left.name != right.name ||
        left.color != right.color ||
        left.region != right.region) {
      return false;
    }
  }
  return true;
}

bool _sameNetworkMapStations(
  List<NetworkMapStation> a,
  List<NetworkMapStation> b,
) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    final left = a[index];
    final right = b[index];
    if (left.id != right.id ||
        left.nameKo != right.nameKo ||
        left.lineId != right.lineId ||
        !_sameNetworkMapPosition(left.position, right.position)) {
      return false;
    }
  }
  return true;
}

bool _sameNetworkMapPosition(NetworkMapPosition a, NetworkMapPosition b) {
  return a.x == b.x &&
      a.y == b.y &&
      a.labelDx == b.labelDx &&
      a.labelDy == b.labelDy &&
      a.labelPolygon == b.labelPolygon &&
      a.upPath == b.upPath &&
      a.downPath == b.downPath &&
      a.sourceId == b.sourceId;
}

bool _sameNetworkMapEdges(List<NetworkMapEdge> a, List<NetworkMapEdge> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var index = 0; index < a.length; index += 1) {
    final left = a[index];
    final right = b[index];
    if (left.id != right.id ||
        left.lineId != right.lineId ||
        left.fromStationId != right.fromStationId ||
        left.toStationId != right.toStationId) {
      return false;
    }
  }
  return true;
}

class _RouteMapViewportRenderer extends StatelessWidget {
  const _RouteMapViewportRenderer({
    required this.asset,
    required this.camera,
    required this.presentedCamera,
    required this.visualCamera,
    required this.onControllerCreated,
  });

  final _RouteMapAsset asset;
  final MapCameraState camera;
  final MapCameraState presentedCamera;
  final MapCameraState visualCamera;
  final ValueChanged<RouteMapRendererController> onControllerCreated;

  @override
  Widget build(BuildContext context) {
    if (_isWidgetTest) {
      return const ColoredBox(
        key: Key('routeMapViewportRenderer'),
        color: Colors.white,
      );
    }
    final renderer = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidRouteMapViewportWebView(
        assetPath: asset.path,
        mimeType: asset.mimeType,
        camera: camera,
        onControllerCreated: onControllerCreated,
      ),
      TargetPlatform.iOS => IosRouteMapViewportWebView(
        assetPath: asset.path,
        mimeType: asset.mimeType,
        camera: camera,
        onControllerCreated: onControllerCreated,
      ),
      _ => const ColoredBox(color: Colors.white),
    };
    return ClipRect(
      child: Transform(
        transform: networkMapRendererFrameTransform(
          rendererCamera: presentedCamera,
          visualCamera: networkMapRendererTransformVisualCamera(
            rendererCamera: presentedCamera,
            visualCamera: visualCamera,
          ),
        ),
        child: KeyedSubtree(
          key: const Key('routeMapViewportRenderer'),
          child: renderer,
        ),
      ),
    );
  }
}

class _OriginalRouteMapUnavailable extends StatelessWidget {
  const _OriginalRouteMapUnavailable();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(
        child: Text(
          '노선도를 불러오지 못했어요',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

bool get _isWidgetTest {
  var isTest = false;
  assert(() {
    isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'AutomatedTest',
    );
    return true;
  }());
  return isTest;
}

String _displayRegionName(String region) {
  return switch (region) {
    '부산권' => '부산',
    '광주권' => '광주',
    '대구권' => '대구',
    '대전권' => '대전',
    _ => region,
  };
}

MapCameraState _cameraForBounds(
  Rect bounds,
  BoxConstraints constraints, {
  required Rect sourceBounds,
  bool contain = false,
  double minScale = _minMapScale,
  int revision = 0,
}) {
  final viewportWidth = constraints.hasBoundedWidth
      ? constraints.maxWidth
      : 0.0;
  final viewportHeight = constraints.hasBoundedHeight
      ? constraints.maxHeight
      : 0.0;
  if (viewportWidth <= 0 || viewportHeight <= 0) {
    return MapCameraState(
      sourceBounds: sourceBounds,
      viewportSize: Size.zero,
      center: sourceBounds.center,
      scale: minScale,
      minScale: minScale,
      maxScale: _maxMapScale,
      revision: revision,
    );
  }
  final widthScale = viewportWidth / bounds.width;
  final heightScale = viewportHeight / bounds.height;
  final computedScale = contain
      ? math.min(widthScale, heightScale)
      : math.max(widthScale, heightScale);
  final initialScale = computedScale.clamp(minScale, _maxMapScale).toDouble();
  return MapCameraState(
    sourceBounds: sourceBounds,
    viewportSize: Size(viewportWidth, viewportHeight),
    center: bounds.center,
    scale: initialScale,
    minScale: minScale,
    maxScale: _maxMapScale,
    revision: revision,
  ).clamped(viewportMargin: 220);
}

@visibleForTesting
MapCameraState networkMapCameraWithMonotonicRevision({
  required MapCameraState current,
  required MapCameraState next,
}) {
  if (next.revision > current.revision) {
    return next;
  }
  return next.copyWith(revision: current.revision + 1);
}

@visibleForTesting
bool networkMapShouldCommitRendererCamera({
  required MapCameraState committed,
  required MapCameraState candidate,
  required Duration elapsedSinceLastCommit,
}) {
  if (elapsedSinceLastCommit >= _routeMapGestureRendererCommitInterval) {
    return true;
  }
  final scaleRatio = candidate.scale / committed.scale;
  if (scaleRatio >= _routeMapGestureMaxScaleRatio ||
      scaleRatio <= 1 / _routeMapGestureMaxScaleRatio) {
    return true;
  }
  final viewportCenter = candidate.viewportSize.center(Offset.zero);
  final committedCandidateCenter = committed.sourceToViewportPoint(
    candidate.center,
  );
  final drift = committedCandidateCenter - viewportCenter;
  return drift.dx.abs() >=
          candidate.viewportSize.width *
              _routeMapGestureMaxTranslationDriftFraction ||
      drift.dy.abs() >=
          candidate.viewportSize.height *
              _routeMapGestureMaxTranslationDriftFraction;
}

@visibleForTesting
MapCameraState networkMapOverscannedRendererCamera(MapCameraState camera) {
  final overscanScale = math.max(
    camera.minScale,
    camera.scale / _routeMapGestureRendererOverscanFactor,
  );
  return camera.copyWith(scale: overscanScale).clamped(viewportMargin: 220);
}

@visibleForTesting
bool networkMapRendererCameraCoversVisual({
  required MapCameraState rendererCamera,
  required MapCameraState visualCamera,
}) {
  const tolerance = 0.001;
  final rendererRect = rendererCamera.visibleSourceRect;
  final visualRect = visualCamera.visibleSourceRect;
  return rendererRect.left <= visualRect.left + tolerance &&
      rendererRect.top <= visualRect.top + tolerance &&
      rendererRect.right >= visualRect.right - tolerance &&
      rendererRect.bottom >= visualRect.bottom - tolerance;
}

@visibleForTesting
MapCameraState? networkMapRendererCommitBasisCamera({
  required MapCameraState? presentedCamera,
  required MapCameraState? requestedCamera,
  required MapCameraState visualCamera,
}) {
  if (requestedCamera != null &&
      networkMapRendererCameraCoversVisual(
        rendererCamera: requestedCamera,
        visualCamera: visualCamera,
      )) {
    return requestedCamera;
  }
  return presentedCamera ?? requestedCamera;
}

@visibleForTesting
MapCameraState networkMapRendererCameraForSkippedCommit({
  required MapCameraState? requestedCamera,
  required MapCameraState candidateCamera,
  required MapCameraState visualCamera,
}) {
  if (requestedCamera != null &&
      networkMapRendererCameraCoversVisual(
        rendererCamera: requestedCamera,
        visualCamera: visualCamera,
      )) {
    return requestedCamera;
  }
  return candidateCamera;
}

@visibleForTesting
bool networkMapShouldAcceptPresentedRendererRevision({
  required int revision,
  required MapCameraState? presentedCamera,
  required MapCameraState? requestedCamera,
}) {
  final presentedRevision = presentedCamera?.revision;
  if (presentedRevision != null && revision < presentedRevision) {
    return false;
  }
  final requestedRevision = requestedCamera?.revision;
  if (requestedRevision != null && revision < requestedRevision) {
    return false;
  }
  return true;
}

@visibleForTesting
MapCameraState networkMapRendererTransformVisualCamera({
  required MapCameraState rendererCamera,
  required MapCameraState visualCamera,
}) {
  return networkMapRendererCameraCoversVisual(
        rendererCamera: rendererCamera,
        visualCamera: visualCamera,
      )
      ? visualCamera
      : rendererCamera;
}

@visibleForTesting
Matrix4 networkMapRendererFrameTransform({
  required MapCameraState rendererCamera,
  required MapCameraState visualCamera,
}) {
  return visualCamera.sourceToViewport
    ..multiply(rendererCamera.viewportToSource);
}

Rect _sourceRectToViewport(Rect sourceRect, MapCameraState camera) {
  final topLeft = camera.sourceToViewportPoint(sourceRect.topLeft);
  final bottomRight = camera.sourceToViewportPoint(sourceRect.bottomRight);
  return Rect.fromLTRB(
    math.min(topLeft.dx, bottomRight.dx),
    math.min(topLeft.dy, bottomRight.dy),
    math.max(topLeft.dx, bottomRight.dx),
    math.max(topLeft.dy, bottomRight.dy),
  );
}

double _minimumMapScaleForBounds(Rect bounds, BoxConstraints constraints) {
  final viewportWidth = constraints.hasBoundedWidth ? constraints.maxWidth : 0;
  final viewportHeight = constraints.hasBoundedHeight
      ? constraints.maxHeight
      : 0;
  if (viewportWidth <= 0 ||
      viewportHeight <= 0 ||
      bounds.width <= 0 ||
      bounds.height <= 0) {
    return _minMapScale;
  }
  final fitScale = math.min(
    viewportWidth / bounds.width,
    viewportHeight / bounds.height,
  );
  if (!fitScale.isFinite || fitScale <= 0) {
    return _minMapScale;
  }
  return math.min(_minMapScale, fitScale);
}

Rect _readableBoundsFor(_MapGeometry geometry) {
  final width = math.min(
    geometry.width,
    math.max(320.0, geometry.width * 0.38),
  );
  final height = math.min(
    geometry.height,
    math.max(320.0, geometry.height * 0.38),
  );
  final maxLeft = math.max(0.0, geometry.width - width);
  final maxTop = math.max(0.0, geometry.height - height);
  final left = (geometry.focus.dx - width / 2).clamp(0.0, maxLeft).toDouble();
  final top = (geometry.focus.dy - height / 2).clamp(0.0, maxTop).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

class _MapGeometry {
  _MapGeometry({
    required this.origin,
    required this.focus,
    required this.width,
    required this.height,
    Rect? initialBounds,
    this.overlayStyleScale = 1.0,
    _StationSpatialIndex? stationIndex,
  }) : initialBounds = initialBounds ?? Rect.fromLTWH(0, 0, width, height),
       stationIndex = stationIndex ?? _StationSpatialIndex.empty;

  final Offset origin;
  final Offset focus;
  final double width;
  final double height;
  final Rect initialBounds;
  final double overlayStyleScale;
  final _StationSpatialIndex stationIndex;

  factory _MapGeometry.fromOriginalAsset(
    _RouteMapAsset asset,
    List<NetworkMapStation> stations,
  ) {
    final sourceWidth = asset.coordinateWidth;
    final sourceHeight = asset.coordinateHeight;
    final overlayStyleScale = math.min(
      sourceWidth / asset.width,
      sourceHeight / asset.height,
    );
    final geometry = _MapGeometry(
      origin: Offset.zero,
      focus: Offset(sourceWidth / 2, sourceHeight / 2),
      width: sourceWidth,
      height: sourceHeight,
      initialBounds: _readableBoundsFor(
        _MapGeometry(
          origin: Offset.zero,
          focus: Offset(sourceWidth / 2, sourceHeight / 2),
          width: sourceWidth,
          height: sourceHeight,
        ),
      ),
      overlayStyleScale: overlayStyleScale.isFinite && overlayStyleScale > 0
          ? overlayStyleScale
          : 1.0,
    );
    return geometry.copyWith(
      stationIndex: _StationSpatialIndex.fromStations(stations, geometry),
    );
  }

  factory _MapGeometry.fromStations(List<NetworkMapStation> stations) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = 0.0;
    var maxY = 0.0;
    final stationXs = <double>[];
    final stationYs = <double>[];
    for (final station in stations) {
      stationXs.add(station.position.x.toDouble());
      stationYs.add(station.position.y.toDouble());
      final point = Rect.fromCircle(
        center: Offset(
          station.position.x.toDouble(),
          station.position.y.toDouble(),
        ),
        radius: 18,
      );
      minX = math.min(minX, point.left);
      minY = math.min(minY, point.top);
      maxX = math.max(maxX, point.right);
      maxY = math.max(maxY, point.bottom);
      for (final pathData in [
        station.position.upPath,
        station.position.downPath,
      ]) {
        if (pathData.isEmpty) {
          continue;
        }
        final bounds = _cachedRouteMapPath(pathData, Offset.zero).bounds;
        minX = math.min(minX, bounds.left);
        minY = math.min(minY, bounds.top);
        maxX = math.max(maxX, bounds.right);
        maxY = math.max(maxY, bounds.bottom);
      }
      final labelPolygonBounds = _labelPolygonBoundsFor(station);
      if (labelPolygonBounds != null) {
        minX = math.min(minX, labelPolygonBounds.left);
        minY = math.min(minY, labelPolygonBounds.top);
        maxX = math.max(maxX, labelPolygonBounds.right);
        maxY = math.max(maxY, labelPolygonBounds.bottom);
      }
    }
    if (!minX.isFinite || !minY.isFinite) {
      return _MapGeometry(
        origin: Offset.zero,
        focus: Offset(430, 280),
        width: 860,
        height: 560,
      );
    }
    const margin = 54.0;
    final origin = Offset(minX - margin, minY - margin);
    final geometry = _MapGeometry(
      origin: origin,
      focus: Offset(
        _median(stationXs) - origin.dx,
        _median(stationYs) - origin.dy,
      ),
      width: math.max(860, maxX - minX + margin * 2),
      height: math.max(560, maxY - minY + margin * 2),
    );
    final result = _MapGeometry(
      origin: geometry.origin,
      focus: geometry.focus,
      width: geometry.width,
      height: geometry.height,
      initialBounds: _readableBoundsFor(geometry),
    );
    return result.copyWith(
      stationIndex: _StationSpatialIndex.fromStations(stations, result),
    );
  }

  double x(NetworkMapStation station) => station.position.x - origin.dx;

  double y(NetworkMapStation station) => station.position.y - origin.dy;

  _MapGeometry copyWith({_StationSpatialIndex? stationIndex}) {
    return _MapGeometry(
      origin: origin,
      focus: focus,
      width: width,
      height: height,
      initialBounds: initialBounds,
      overlayStyleScale: overlayStyleScale,
      stationIndex: stationIndex ?? this.stationIndex,
    );
  }
}

class _StationSpatialIndex {
  _StationSpatialIndex._({
    required Map<_StationSpatialCell, List<NetworkMapStation>> buckets,
    required Map<String, int> stationOrder,
  }) : _buckets = buckets, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _stationOrder = stationOrder;

  static final empty = _StationSpatialIndex._(
    buckets: const {},
    stationOrder: const {},
  );

  static const _cellSize = 256.0;

  final Map<_StationSpatialCell, List<NetworkMapStation>> _buckets;
  final Map<String, int> _stationOrder;

  factory _StationSpatialIndex.fromStations(
    List<NetworkMapStation> stations,
    _MapGeometry geometry,
  ) {
    final buckets = <_StationSpatialCell, List<NetworkMapStation>>{};
    final stationOrder = <String, int>{};
    for (var index = 0; index < stations.length; index += 1) {
      final station = stations[index];
      final key = _stationGeometryKey(station);
      stationOrder[key] = index;
      final bounds = _stationHitRect(station, geometry);
      for (final cell in _cellsFor(bounds)) {
        buckets.putIfAbsent(cell, () => []).add(station);
      }
    }
    return _StationSpatialIndex._(buckets: buckets, stationOrder: stationOrder);
  }

  List<NetworkMapStation> query(Rect sourceBounds) {
    if (_buckets.isEmpty || sourceBounds.isEmpty) {
      return const [];
    }
    final byKey = <String, NetworkMapStation>{};
    for (final cell in _cellsFor(sourceBounds)) {
      for (final station in _buckets[cell] ?? const <NetworkMapStation>[]) {
        byKey[_stationGeometryKey(station)] = station;
      }
    }
    final result = byKey.values.toList(growable: false);
    result.sort((a, b) {
      final aOrder = _stationOrder[_stationGeometryKey(a)] ?? 0;
      final bOrder = _stationOrder[_stationGeometryKey(b)] ?? 0;
      return aOrder.compareTo(bOrder);
    });
    return result;
  }

  static Iterable<_StationSpatialCell> _cellsFor(Rect bounds) sync* {
    final left = _cellFor(bounds.left);
    final right = _cellFor(bounds.right);
    final top = _cellFor(bounds.top);
    final bottom = _cellFor(bounds.bottom);
    for (var x = left; x <= right; x += 1) {
      for (var y = top; y <= bottom; y += 1) {
        yield _StationSpatialCell(x, y);
      }
    }
  }

  static int _cellFor(double value) => (value / _cellSize).floor();
}

@immutable
class _StationSpatialCell {
  const _StationSpatialCell(this.x, this.y);

  final int x;
  final int y;

  @override
  bool operator ==(Object other) {
    return other is _StationSpatialCell && other.x == x && other.y == y;
  }

  @override
  int get hashCode => Object.hash(x, y);
}

const _maximumStationHitDistance = 24.0;

List<NetworkMapStation> _canonicalStations(
  Iterable<NetworkMapStation> stations,
  _MapGeometry geometry,
) {
  final canonicalStations = <NetworkMapStation>[];
  for (final station in stations) {
    final existingIndex = canonicalStations.indexWhere((existing) {
      return existing.id == station.id &&
          _isOverlappingStationGeometry(existing, station, geometry);
    });
    if (existingIndex == -1) {
      canonicalStations.add(station);
      continue;
    }
    final existing = canonicalStations[existingIndex];
    if (_stationGeometryPriority(station) >
        _stationGeometryPriority(existing)) {
      canonicalStations[existingIndex] = station;
    }
  }
  return canonicalStations;
}

bool _isOverlappingStationGeometry(
  NetworkMapStation a,
  NetworkMapStation b,
  _MapGeometry geometry,
) {
  return _stationHitRect(
    a,
    geometry,
  ).inflate(8).overlaps(_stationHitRect(b, geometry).inflate(8));
}

List<NetworkMapStation> _visibleCanonicalStations({
  required _MapGeometry geometry,
  required MapCameraState camera,
}) {
  final visibleSourceRect = camera.visibleSourceRect.inflate(96 / camera.scale);
  return _canonicalStations(
    geometry.stationIndex.query(visibleSourceRect).where((station) {
      return _stationHitRect(station, geometry).overlaps(visibleSourceRect);
    }),
    geometry,
  );
}

int _stationGeometryPriority(NetworkMapStation station) {
  if (station.position.labelPolygon.isNotEmpty) {
    return 3;
  }
  if (station.position.upPath.isNotEmpty ||
      station.position.downPath.isNotEmpty) {
    return 2;
  }
  return 1;
}

Rect _stationHitRect(
  NetworkMapStation station,
  _MapGeometry geometry, {
  double nodeRadius = 24,
  double labelHeight = 40,
}) {
  final node = Rect.fromCenter(
    center: Offset(geometry.x(station), geometry.y(station)),
    width: nodeRadius * 2,
    height: nodeRadius * 2,
  );
  final labelOffset = _labelOffsetFor(station);
  final labelPolygon = _labelPolygonFor(station, geometry);
  if (labelPolygon != null) {
    return node.expandToInclude(_boundsForPolygon(labelPolygon));
  }
  final labelCenter = Offset(
    geometry.x(station) + labelOffset.dx,
    geometry.y(station) + labelOffset.dy,
  );
  final label = Rect.fromCenter(
    center: labelCenter,
    width: math.max(64, station.nameKo.characters.length * 18 + 32),
    height: labelHeight,
  );
  return node.expandToInclude(label);
}

NetworkMapStation? _stationAtViewportPosition(
  Offset viewportPosition,
  _MapGeometry geometry, {
  required MapCameraState camera,
}) {
  final safeScale = camera.scale > 0 ? camera.scale : 1.0;
  final sourcePosition = camera.viewportToSourcePoint(viewportPosition);
  final sourceQuery = Rect.fromCircle(
    center: sourcePosition,
    radius: _maximumStationHitDistance / safeScale,
  );
  NetworkMapStation? bestStation;
  _StationTapScore? bestScore;
  for (final station in geometry.stationIndex.query(sourceQuery)) {
    final score = _stationTapScore(viewportPosition, station, geometry, camera);
    if (score == null) {
      continue;
    }
    if (bestScore == null || score.compareTo(bestScore) < 0) {
      bestScore = score;
      bestStation = station;
    }
  }
  return bestStation;
}

_StationTapScore? _stationTapScore(
  Offset viewportPosition,
  NetworkMapStation station,
  _MapGeometry geometry,
  MapCameraState camera,
) {
  final safeScale = camera.scale > 0 ? camera.scale : 1.0;
  final nodeCenter = camera.sourceToViewportPoint(
    Offset(geometry.x(station), geometry.y(station)),
  );
  final nodeHitRect = Rect.fromCenter(
    center: nodeCenter,
    width: _maximumStationHitDistance * 2,
    height: _maximumStationHitDistance * 2,
  );
  final containsNode = nodeHitRect.contains(viewportPosition);
  final nodeDistance = (viewportPosition - nodeCenter).distance;
  var bestHitDistance = containsNode ? 0.0 : double.infinity;
  var bestSelectionDistance = containsNode ? nodeDistance : double.infinity;
  var containsShape = containsNode;
  final labelPolygon = _labelPolygonFor(station, geometry);
  if (labelPolygon != null) {
    final viewportPolygon = [
      for (final point in labelPolygon) camera.sourceToViewportPoint(point),
    ];
    final polygonDistance = math.sqrt(
      _distanceSquaredToPolygon(viewportPosition, viewportPolygon),
    );
    bestHitDistance = math.min(bestHitDistance, polygonDistance);
    if (polygonDistance <= _maximumStationHitDistance) {
      bestSelectionDistance = math.min(bestSelectionDistance, polygonDistance);
    }
    containsShape = containsShape || polygonDistance == 0;
  } else {
    final labelRect = _sourceRectToViewport(
      _stationLabelRect(station, geometry, labelHeight: 40 / safeScale),
      camera,
    );
    final labelDistance = _distanceToRect(viewportPosition, labelRect);
    bestHitDistance = math.min(bestHitDistance, labelDistance);
    if (labelDistance <= _maximumStationHitDistance) {
      bestSelectionDistance = math.min(
        bestSelectionDistance,
        (viewportPosition - labelRect.center).distance,
      );
    }
    containsShape = containsShape || labelDistance == 0;
  }
  if (bestHitDistance > _maximumStationHitDistance) {
    return null;
  }
  return _StationTapScore(
    containsNode: containsNode,
    containsShape: containsShape,
    screenDistance: bestSelectionDistance.isFinite
        ? bestSelectionDistance
        : bestHitDistance,
    stableKey: _stationGeometryKey(station),
  );
}

Rect _stationLabelRect(
  NetworkMapStation station,
  _MapGeometry geometry, {
  double labelHeight = 40,
}) {
  final labelOffset = _labelOffsetFor(station);
  final labelCenter = Offset(
    geometry.x(station) + labelOffset.dx,
    geometry.y(station) + labelOffset.dy,
  );
  return Rect.fromCenter(
    center: labelCenter,
    width: math.max(64, station.nameKo.characters.length * 18 + 32),
    height: labelHeight,
  );
}

double _distanceToRect(Offset point, Rect rect) {
  if (rect.contains(point)) {
    return 0;
  }
  final dx = point.dx < rect.left
      ? rect.left - point.dx
      : point.dx > rect.right
      ? point.dx - rect.right
      : 0.0;
  final dy = point.dy < rect.top
      ? rect.top - point.dy
      : point.dy > rect.bottom
      ? point.dy - rect.bottom
      : 0.0;
  return math.sqrt(dx * dx + dy * dy);
}

class _StationTapScore implements Comparable<_StationTapScore> {
  const _StationTapScore({
    required this.containsNode,
    required this.containsShape,
    required this.screenDistance,
    required this.stableKey,
  });

  final bool containsNode;
  final bool containsShape;
  final double screenDistance;
  final String stableKey;

  @override
  int compareTo(_StationTapScore other) {
    final nodeComparison = _scoreBool(
      containsNode,
    ).compareTo(_scoreBool(other.containsNode));
    if (nodeComparison != 0) {
      return nodeComparison;
    }
    final containsComparison = _scoreBool(
      containsShape,
    ).compareTo(_scoreBool(other.containsShape));
    if (containsComparison != 0) {
      return containsComparison;
    }
    final distanceComparison = screenDistance.compareTo(other.screenDistance);
    if (distanceComparison != 0) {
      return distanceComparison;
    }
    return stableKey.compareTo(other.stableKey);
  }

  static int _scoreBool(bool value) => value ? 0 : 1;
}

String _stationGeometryKey(NetworkMapStation station) {
  return '${station.id}:${station.lineId}';
}

Rect? _labelPolygonBoundsFor(NetworkMapStation station) {
  final polygon = _parseLabelPolygon(station.position.labelPolygon);
  return polygon == null ? null : _boundsForPolygon(polygon);
}

List<Offset>? _labelPolygonFor(
  NetworkMapStation station,
  _MapGeometry geometry,
) {
  final polygon = _parseLabelPolygon(station.position.labelPolygon);
  if (polygon == null) {
    return null;
  }
  return [
    for (final point in polygon)
      Offset(point.dx - geometry.origin.dx, point.dy - geometry.origin.dy),
  ];
}

List<Offset>? _parseLabelPolygon(String value) {
  if (value.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List || decoded.length < 3) {
      return null;
    }
    final points = <Offset>[];
    for (final rawPoint in decoded) {
      if (rawPoint is! Map) {
        return null;
      }
      final x = rawPoint['x'];
      final y = rawPoint['y'];
      if (x is! num || y is! num) {
        return null;
      }
      final dx = x.toDouble();
      final dy = y.toDouble();
      if (!dx.isFinite || !dy.isFinite || dx < 0 || dy < 0) {
        return null;
      }
      points.add(Offset(dx, dy));
    }
    return points;
  } on FormatException {
    return null;
  }
}

Rect _boundsForPolygon(List<Offset> polygon) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final point in polygon) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

double _distanceSquaredToPolygon(Offset point, List<Offset> polygon) {
  if (_pointInPolygon(point, polygon)) {
    return 0;
  }
  var best = double.infinity;
  for (var index = 0; index < polygon.length; index += 1) {
    best = math.min(
      best,
      _distanceSquaredToSegment(
        point,
        polygon[index],
        polygon[(index + 1) % polygon.length],
      ),
    );
  }
  return best;
}

bool _pointInPolygon(Offset point, List<Offset> polygon) {
  var inside = false;
  for (
    var index = 0, previous = polygon.length - 1;
    index < polygon.length;
    previous = index, index += 1
  ) {
    final currentPoint = polygon[index];
    final previousPoint = polygon[previous];
    final crossesY =
        (currentPoint.dy > point.dy) != (previousPoint.dy > point.dy);
    if (!crossesY) {
      continue;
    }
    final intersectionX =
        (previousPoint.dx - currentPoint.dx) *
            (point.dy - currentPoint.dy) /
            (previousPoint.dy - currentPoint.dy) +
        currentPoint.dx;
    if (point.dx < intersectionX) {
      inside = !inside;
    }
  }
  return inside;
}

double _distanceSquaredToSegment(Offset point, Offset start, Offset end) {
  final segment = end - start;
  final lengthSquared = segment.distanceSquared;
  if (lengthSquared == 0) {
    return (point - start).distanceSquared;
  }
  final t =
      (((point.dx - start.dx) * segment.dx) +
          ((point.dy - start.dy) * segment.dy)) /
      lengthSquared;
  final clampedT = t.clamp(0.0, 1.0).toDouble();
  final projection = Offset(
    start.dx + segment.dx * clampedT,
    start.dy + segment.dy * clampedT,
  );
  return (point - projection).distanceSquared;
}

double _median(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  values.sort();
  return values[values.length ~/ 2];
}

bool _usesOfficialRouteMapSource(NetworkMapStation station) {
  return station.position.sourceId.endsWith('-cyberstation') ||
      station.position.sourceId == 'qa-wikimedia-seoul-svg-coordinate';
}

Offset _labelOffsetFor(NetworkMapStation station) {
  if (_usesOfficialRouteMapSource(station)) {
    return Offset(
      station.position.labelDx.toDouble(),
      station.position.labelDy.toDouble(),
    );
  }
  final pathData = station.position.downPath.isNotEmpty
      ? station.position.downPath
      : station.position.upPath;
  if (pathData.isEmpty) {
    return const Offset(8, 3);
  }
  final bounds = _cachedRouteMapPath(pathData, Offset.zero).bounds;
  if (bounds.width > bounds.height * 1.2) {
    return const Offset(0, 12);
  }
  if (bounds.height > bounds.width * 1.2) {
    return const Offset(9, 3);
  }
  return const Offset(8, -8);
}

class _StationHitTarget extends StatelessWidget {
  const _StationHitTarget({
    required this.station,
    required this.onTap,
    super.key,
  });

  final NetworkMapStation station;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: station.displayName,
      onTap: onTap,
      child: const SizedBox.expand(),
    );
  }
}

Map<String, List<NetworkMapLine>> _stationLinesById(NetworkMapData data) {
  final linesById = {for (final line in data.lines) line.id: line};
  final stationLinesById = <String, List<NetworkMapLine>>{};

  void addLine(String stationId, String lineId) {
    final line = linesById[lineId];
    if (line == null) {
      return;
    }
    final stationLines = stationLinesById.putIfAbsent(stationId, () => []);
    if (!stationLines.any((existing) => existing.id == line.id)) {
      stationLines.add(line);
    }
  }

  if (data.stationLineMemberships.isNotEmpty) {
    for (final membership in data.stationLineMemberships) {
      addLine(membership.stationId, membership.lineId);
    }
  } else {
    for (final station in data.stations) {
      addLine(station.id, station.lineId);
    }
  }
  return stationLinesById;
}

Path _pathFromSvg(String data) {
  final tokens = RegExp(
    r'[A-Za-z]|-?\d+(?:\.\d+)?',
  ).allMatches(data).map((m) => m.group(0)!).toList();
  final path = Path();
  var index = 0;
  var command = '';
  var current = Offset.zero;
  var lastControl = Offset.zero;
  while (index < tokens.length) {
    if (RegExp(r'^[A-Za-z]$').hasMatch(tokens[index])) {
      command = tokens[index++];
    }
    double number() => double.parse(tokens[index++]);
    switch (command) {
      case 'M':
        current = Offset(number(), number());
        path.moveTo(current.dx, current.dy);
        break;
      case 'm':
        current += Offset(number(), number());
        path.moveTo(current.dx, current.dy);
        break;
      case 'L':
        current = Offset(number(), number());
        path.lineTo(current.dx, current.dy);
        break;
      case 'l':
        current += Offset(number(), number());
        path.lineTo(current.dx, current.dy);
        break;
      case 'H':
        current = Offset(number(), current.dy);
        path.lineTo(current.dx, current.dy);
        break;
      case 'h':
        current = Offset(current.dx + number(), current.dy);
        path.lineTo(current.dx, current.dy);
        break;
      case 'V':
        current = Offset(current.dx, number());
        path.lineTo(current.dx, current.dy);
        break;
      case 'v':
        current = Offset(current.dx, current.dy + number());
        path.lineTo(current.dx, current.dy);
        break;
      case 'C':
        final c1 = Offset(number(), number());
        final c2 = Offset(number(), number());
        current = Offset(number(), number());
        lastControl = c2;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
        break;
      case 'c':
        final c1 = current + Offset(number(), number());
        final c2 = current + Offset(number(), number());
        current += Offset(number(), number());
        lastControl = c2;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
        break;
      case 'S':
        final c1 = current * 2 - lastControl;
        final c2 = Offset(number(), number());
        current = Offset(number(), number());
        lastControl = c2;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
        break;
      case 's':
        final c1 = current * 2 - lastControl;
        final c2 = current + Offset(number(), number());
        current += Offset(number(), number());
        lastControl = c2;
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
        break;
      case 'Q':
        final c = Offset(number(), number());
        current = Offset(number(), number());
        lastControl = c;
        path.quadraticBezierTo(c.dx, c.dy, current.dx, current.dy);
        break;
      case 'q':
        final c = current + Offset(number(), number());
        current += Offset(number(), number());
        lastControl = c;
        path.quadraticBezierTo(c.dx, c.dy, current.dx, current.dy);
        break;
      default:
        return path;
    }
  }
  return path;
}

class _StationSheet extends StatelessWidget {
  const _StationSheet({
    required this.station,
    required this.lines,
    required this.onSetOrigin,
    required this.onSetDestination,
    required this.onOpenRouteSearch,
  });

  final NetworkMapStation station;
  final List<NetworkMapLine> lines;
  final VoidCallback onSetOrigin;
  final VoidCallback onSetDestination;
  final VoidCallback onOpenRouteSearch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      key: const Key('networkMapStationSheet'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final line in lines) _StationLineChip(line: line),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              station.displayName,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              '노선 순서와 좌표 기준으로 표시됩니다.',
              style: TextStyle(fontSize: 15, color: Color(0xFF4D6367)),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSetOrigin,
                    child: const Text('출발로 설정'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onSetDestination,
                    child: const Text('도착으로 설정'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.info_outline),
                    label: const Text('역 상세'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onOpenRouteSearch,
                    icon: const Icon(Icons.route),
                    label: const Text('길찾기'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Color _colorFromHex(String value) {
  final normalized = value.replaceFirst('#', '');
  if (normalized.length != 6) {
    return EasySubwayAccessibleColors.mint;
  }
  return Color(int.parse('FF$normalized', radix: 16));
}

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }
  return value
      .whereType<Map<Object?, Object?>>()
      .map((item) => item.cast<String, Object?>())
      .toList(growable: false);
}
