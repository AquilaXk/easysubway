import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  });

  final int x;
  final int y;
  final int labelDx;
  final int labelDy;
  final String upPath;
  final String downPath;
  final String sourceId;

  factory NetworkMapPosition.fromJson(Map<String, Object?> json) {
    return NetworkMapPosition(
      x: json['x'] as int? ?? 0,
      y: json['y'] as int? ?? 0,
      labelDx: json['labelDx'] as int? ?? 0,
      labelDy: json['labelDy'] as int? ?? 0,
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
  String? _selectedLineId;
  late Future<NetworkMapData> _future = _loadMap();

  Future<NetworkMapData> _loadMap() {
    return widget.repository.getNetworkMap(
      region: _selectedRegion,
      lineId: _selectedLineId,
    );
  }

  void _reload({String? region, String? lineId}) {
    setState(() {
      final isChangingRegion = region != null && region != _selectedRegion;
      _selectedRegion = region ?? _selectedRegion;
      _selectedLineId = isChangingRegion ? null : lineId;
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
                    selectedLineId: _selectedLineId,
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
                      const SizedBox(height: 8),
                      _LineFilterMenu(
                        lines: data.lines,
                        selectedLineId: _selectedLineId,
                        onSelected: (lineId) => _reload(lineId: lineId),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 14,
                  bottom: 14,
                  child: SizedBox(
                    width: 180,
                    height: 48,
                    child: FilledButton.icon(
                      key: const Key('networkMapListButton'),
                      onPressed: () => _showMapList(data),
                      icon: const Icon(Icons.list_alt),
                      label: const Text('노선별로 보기'),
                    ),
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

  void _showMapList(NetworkMapData data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return _NetworkMapListSheet(
          data: data,
          onStationTap: (station, lines) {
            Navigator.of(context).pop();
            _showStationSheet(station, lines);
          },
        );
      },
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

class _LineFilterMenu extends StatelessWidget {
  const _LineFilterMenu({
    required this.lines,
    required this.selectedLineId,
    required this.onSelected,
  });

  final List<NetworkMapLine> lines;
  final String? selectedLineId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    NetworkMapLine? selectedLine;
    for (final line in lines) {
      if (line.id == selectedLineId) {
        selectedLine = line;
        break;
      }
    }
    final label = selectedLine?.shortName ?? '전체 노선';
    return SizedBox(
      key: const Key('networkMapLineFilter'),
      width: 142,
      height: EasySubwayTouchTarget.general,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        initialValue: selectedLineId ?? '',
        onSelected: (lineId) => onSelected(lineId.isEmpty ? null : lineId),
        itemBuilder: (context) => [
          const PopupMenuItem<String>(value: '', child: Text('전체 노선')),
          for (final line in lines)
            PopupMenuItem<String>(value: line.id, child: Text(line.shortName)),
        ],
        child: _RegionMenuButton(label: label, semanticLabel: '노선: $label'),
      ),
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
  const _NetworkMapCanvas({
    required this.data,
    required this.selectedLineId,
    required this.onStationTap,
  });

  final NetworkMapData data;
  final String? selectedLineId;
  final void Function(NetworkMapStation station, List<NetworkMapLine> lines)
  onStationTap;

  @override
  State<_NetworkMapCanvas> createState() => _NetworkMapCanvasState();
}

const _minMapScale = 0.08;
const _maxMapScale = 4.8;

class _NetworkMapCanvasState extends State<_NetworkMapCanvas>
    with WidgetsBindingObserver {
  String? _layoutKey;
  MapCameraState? _camera;
  MapCameraState? _gestureStartCamera;
  Offset? _gestureStartFocalPoint;
  RouteMapRendererHealthMonitor? _rendererMonitor;
  RouteMapRendererController? _rendererController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_rendererMonitor?.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive || AppLifecycleState.paused:
        _ignoreRendererLifecycleFailure(_rendererMonitor?.trimMemory());
      case AppLifecycleState.detached:
        final monitor = _rendererMonitor;
        _rendererMonitor = null;
        _rendererController = null;
        _ignoreRendererLifecycleFailure(monitor?.disposeRenderer());
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

  @override
  Widget build(BuildContext context) {
    final linesById = {for (final line in widget.data.lines) line.id: line};
    final stationsById = <String, NetworkMapStation>{};
    for (final station in widget.data.stations) {
      stationsById[_mapStationKey(station)] = station;
      stationsById.putIfAbsent(station.id, () => station);
    }
    final stationLinesById = _stationLinesById(widget.data);
    final mapAsset = _routeMapAssetForRegion(widget.data.selectedRegion);
    return Container(
      key: const Key('networkMapSurface'),
      decoration: const BoxDecoration(color: Colors.white),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = mapAsset == null
              ? _MapGeometry.fromStations(widget.data.stations)
              : _MapGeometry.fromOriginalAsset(mapAsset);
          final fullBounds = Rect.fromLTWH(
            0,
            0,
            geometry.width,
            geometry.height,
          );
          final minScale = _minimumMapScaleForBounds(fullBounds, constraints);
          final layoutKey =
              '${widget.data.selectedRegion}:${geometry.width}:${geometry.height}:${constraints.maxWidth}:${constraints.maxHeight}';
          if (_layoutKey != layoutKey) {
            _layoutKey = layoutKey;
            _camera = _cameraForBounds(
              geometry.initialBounds,
              constraints,
              sourceBounds: fullBounds,
              minScale: minScale,
            );
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
                    : _RouteMapViewportRenderer(
                        asset: mapAsset,
                        camera: camera,
                        onControllerCreated: _attachRendererController,
                      ),
              ),
              if (widget.selectedLineId != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const Key('networkMapSelectedLineOverlay'),
                      painter: _SelectedLineOverlayPainter(
                        lineId: widget.selectedLineId!,
                        linesById: linesById,
                        stationsById: stationsById,
                        edges: widget.data.edges,
                        geometry: geometry,
                        camera: camera,
                        styleScale: geometry.overlayStyleScale,
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onScaleStart: (details) {
                    _gestureStartCamera = camera;
                    _gestureStartFocalPoint = details.localFocalPoint;
                  },
                  onScaleUpdate: (details) {
                    _updateCameraForGesture(details);
                  },
                  onScaleEnd: (_) {
                    _gestureStartCamera = null;
                    _gestureStartFocalPoint = null;
                  },
                  onTapUp: (details) {
                    _openNearestStation(
                      camera.viewportToSourcePoint(details.localPosition),
                      widget.data.stations,
                      stationLinesById,
                      geometry,
                      camera,
                    );
                  },
                ),
              ),
              for (final station in widget.data.stations)
                if (_stationHitRect(
                  station,
                  geometry,
                ).overlaps(camera.visibleSourceRect.inflate(96 / camera.scale)))
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
    final camera = _camera;
    if (camera == null || camera.viewportSize == Size.zero) {
      return;
    }
    _setCamera(
      camera
          .zoomBy(factor, focalPoint: camera.viewportSize.center(Offset.zero))
          .clamped(viewportMargin: 220),
    );
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

  void _setCamera(MapCameraState camera) {
    final currentCamera = _camera;
    final nextCamera = currentCamera == null
        ? camera
        : networkMapCameraWithMonotonicRevision(
            current: currentCamera,
            next: camera,
          );
    if (_camera == nextCamera) {
      return;
    }
    setState(() {
      _camera = nextCamera;
    });
  }

  void _openNearestStation(
    Offset sourcePosition,
    List<NetworkMapStation> stations,
    Map<String, List<NetworkMapLine>> stationLinesById,
    _MapGeometry geometry,
    MapCameraState camera,
  ) {
    final station = _stationAtMapPosition(
      sourcePosition,
      stations,
      geometry,
      sceneHitRadius: 24 / (camera.scale > 0 ? camera.scale : 1),
      selectedLineId: widget.selectedLineId,
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
    unawaited(_rendererMonitor?.stop());
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
    if (event is RouteMapRendererDisposed &&
        identical(_rendererMonitor, monitor)) {
      _rendererMonitor = null;
      _rendererController = null;
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
      case RouteMapRendererCreated() ||
          RouteMapRendererAssetLoading() ||
          RouteMapRendererAssetReady() ||
          RouteMapRendererCameraRequested() ||
          RouteMapRendererFramePresented() ||
          RouteMapRendererFailed() ||
          RouteMapRendererDisposed():
        break;
    }
  }
}

class _SelectedLineOverlayPainter extends CustomPainter {
  const _SelectedLineOverlayPainter({
    required this.lineId,
    required this.linesById,
    required this.stationsById,
    required this.edges,
    required this.geometry,
    required this.camera,
    required this.styleScale,
  });

  final String lineId;
  final Map<String, NetworkMapLine> linesById;
  final Map<String, NetworkMapStation> stationsById;
  final List<NetworkMapEdge> edges;
  final _MapGeometry geometry;
  final MapCameraState camera;
  final double styleScale;

  @override
  void paint(Canvas canvas, Size size) {
    final line = linesById[lineId];
    if (line == null) {
      return;
    }
    final lineColor = _colorFromHex(line.color);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: 0.58),
    );
    canvas
      ..save()
      ..transform(camera.sourceToViewport.storage);
    final pathPaint = Paint()
      ..color = lineColor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 14 * styleScale
      ..style = PaintingStyle.stroke;
    for (final edge in edges) {
      if (edge.lineId != lineId) {
        continue;
      }
      final from = stationsById[edge.fromStationId];
      final to = stationsById[edge.toStationId];
      if (from == null || to == null) {
        continue;
      }
      final segmentPath = _segmentPath(from, to);
      if (segmentPath == null) {
        canvas.drawLine(
          Offset(geometry.x(from), geometry.y(from)),
          Offset(geometry.x(to), geometry.y(to)),
          pathPaint,
        );
      } else {
        _drawScaledPath(canvas, segmentPath, pathPaint, geometry);
      }
    }
    final stationBorderPaint = Paint()..color = lineColor;
    final stationFillPaint = Paint()..color = Colors.white;
    for (final station in stationsById.values.toSet()) {
      if (station.lineId != lineId) {
        continue;
      }
      final center = Offset(geometry.x(station), geometry.y(station));
      canvas.drawCircle(center, 13 * styleScale, stationBorderPaint);
      canvas.drawCircle(center, 7 * styleScale, stationFillPaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SelectedLineOverlayPainter oldDelegate) {
    return oldDelegate.lineId != lineId ||
        oldDelegate.linesById != linesById ||
        oldDelegate.stationsById != stationsById ||
        oldDelegate.edges != edges ||
        oldDelegate.geometry != geometry ||
        oldDelegate.camera != camera ||
        oldDelegate.styleScale != styleScale;
  }
}

Path? _segmentPath(NetworkMapStation from, NetworkMapStation to) {
  for (final pathData in [
    from.position.downPath,
    to.position.upPath,
    from.position.upPath,
    to.position.downPath,
  ]) {
    if (pathData.trim().isEmpty) {
      continue;
    }
    final path = _pathFromSvg(pathData);
    final bounds = path.getBounds().inflate(2);
    final fromPoint = Offset(
      from.position.x.toDouble(),
      from.position.y.toDouble(),
    );
    final toPoint = Offset(to.position.x.toDouble(), to.position.y.toDouble());
    if (bounds.contains(fromPoint) && bounds.contains(toPoint)) {
      return path;
    }
  }
  return null;
}

void _drawScaledPath(
  Canvas canvas,
  Path path,
  Paint paint,
  _MapGeometry geometry,
) {
  canvas
    ..save()
    ..translate(-geometry.origin.dx, -geometry.origin.dy);
  canvas.drawPath(
    path,
    Paint()
      ..color = paint.color
      ..strokeCap = paint.strokeCap
      ..strokeJoin = paint.strokeJoin
      ..strokeWidth = paint.strokeWidth
      ..style = paint.style,
  );
  canvas.restore();
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
          tooltip: '전체 노선도',
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

class _RouteMapViewportRenderer extends StatelessWidget {
  const _RouteMapViewportRenderer({
    required this.asset,
    required this.camera,
    required this.onControllerCreated,
  });

  final _RouteMapAsset asset;
  final MapCameraState camera;
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
    return KeyedSubtree(
      key: const Key('routeMapViewportRenderer'),
      child: renderer,
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
  }) : initialBounds = initialBounds ?? Rect.fromLTWH(0, 0, width, height);

  final Offset origin;
  final Offset focus;
  final double width;
  final double height;
  final Rect initialBounds;
  final double overlayStyleScale;

  factory _MapGeometry.fromOriginalAsset(_RouteMapAsset asset) {
    final sourceWidth = asset.coordinateWidth;
    final sourceHeight = asset.coordinateHeight;
    final overlayStyleScale = math.min(
      sourceWidth / asset.width,
      sourceHeight / asset.height,
    );
    return _MapGeometry(
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
        final bounds = _pathFromSvg(pathData).getBounds();
        minX = math.min(minX, bounds.left);
        minY = math.min(minY, bounds.top);
        maxX = math.max(maxX, bounds.right);
        maxY = math.max(maxY, bounds.bottom);
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
    return _MapGeometry(
      origin: geometry.origin,
      focus: geometry.focus,
      width: geometry.width,
      height: geometry.height,
      initialBounds: _readableBoundsFor(geometry),
    );
  }

  double x(NetworkMapStation station) => station.position.x - origin.dx;

  double y(NetworkMapStation station) => station.position.y - origin.dy;
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

NetworkMapStation? _stationAtMapPosition(
  Offset position,
  List<NetworkMapStation> stations,
  _MapGeometry geometry, {
  required double sceneHitRadius,
  String? selectedLineId,
}) {
  NetworkMapStation? bestStation;
  var bestScore = double.infinity;
  for (final station in stations) {
    final hitRect = _stationHitRect(
      station,
      geometry,
      nodeRadius: sceneHitRadius,
      labelHeight: sceneHitRadius * 2,
    );
    if (!hitRect.contains(position)) {
      continue;
    }
    final score =
        _stationTapScore(position, station, geometry) +
        (selectedLineId != null && station.lineId != selectedLineId
            ? 1000000
            : 0);
    if (score < bestScore) {
      bestScore = score;
      bestStation = station;
    }
  }
  return bestStation;
}

double _stationTapScore(
  Offset position,
  NetworkMapStation station,
  _MapGeometry geometry,
) {
  final nodeCenter = Offset(geometry.x(station), geometry.y(station));
  final labelOffset = _labelOffsetFor(station);
  final labelCenter = Offset(
    nodeCenter.dx + labelOffset.dx,
    nodeCenter.dy + labelOffset.dy,
  );
  return math.min(
    (position - nodeCenter).distanceSquared,
    (position - labelCenter).distanceSquared,
  );
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
  final bounds = _pathFromSvg(pathData).getBounds();
  if (bounds.width > bounds.height * 1.2) {
    return const Offset(0, 12);
  }
  if (bounds.height > bounds.width * 1.2) {
    return const Offset(9, 3);
  }
  return const Offset(8, -8);
}

String _mapStationKey(NetworkMapStation station) =>
    '${station.id}:${station.lineId}';

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

class _NetworkMapListSheet extends StatelessWidget {
  const _NetworkMapListSheet({required this.data, required this.onStationTap});

  final NetworkMapData data;
  final void Function(NetworkMapStation station, List<NetworkMapLine> lines)
  onStationTap;

  @override
  Widget build(BuildContext context) {
    final stationsByLine = <String, List<NetworkMapStation>>{};
    for (final station in data.stations) {
      stationsByLine.putIfAbsent(station.lineId, () => []).add(station);
    }
    final stationLinesById = _stationLinesById(data);
    return SafeArea(
      key: const Key('networkMapListSheet'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: [
          const Text(
            '노선별 역 보기',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            '노선별 목록에서 역을 선택하세요.',
            style: TextStyle(fontSize: 15, color: Color(0xFF4D6367)),
          ),
          const SizedBox(height: 14),
          if (data.stations.isEmpty)
            const Text(
              '선택한 노선에 표시할 역이 없습니다.',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            )
          else
            for (final line in data.lines)
              if (stationsByLine[line.id]?.isNotEmpty ?? false)
                ExpansionTile(
                  key: Key('networkMapListLine-${line.id}'),
                  initiallyExpanded: true,
                  leading: _LineCircleBadge(line: line, size: 34),
                  title: Text(
                    line.shortName,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  children: [
                    for (final station in stationsByLine[line.id]!)
                      ListTile(
                        key: Key(
                          'networkMapListStation-${station.id}-${station.lineId}',
                        ),
                        title: Text(station.displayName),
                        subtitle: Text(line.shortName),
                        onTap: () => onStationTap(
                          station,
                          stationLinesById[station.id] ?? const [],
                        ),
                      ),
                  ],
                ),
        ],
      ),
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
