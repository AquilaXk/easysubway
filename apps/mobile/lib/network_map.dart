import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'accessible_design.dart';
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
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final List<NetworkMapLine> lines;
  final List<NetworkMapStation> stations;
  final List<NetworkMapEdge> edges;
  final List<NetworkMapPositionSource> positionSources;

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
    );
  }
}

class NetworkMapRegion {
  const NetworkMapRegion({required this.name});

  final String name;

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
      _selectedRegion = region ?? _selectedRegion;
      _selectedLineId = lineId;
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
                  child: _RegionTabs(
                    regions: data.regions,
                    selectedRegion: data.selectedRegion,
                    onSelected: (region) => _reload(region: region),
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
          NavigationDestination(icon: Icon(Icons.bookmark_border), label: '저장'),
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
      height: 40,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        initialValue: selected,
        onSelected: onSelected,
        itemBuilder: (context) => [
          for (final region in visibleRegions)
            PopupMenuItem<String>(value: region.name, child: Text(region.name)),
        ],
        child: _RegionMenuButton(label: selected),
      ),
    );
  }
}

class _RegionMenuButton extends StatelessWidget {
  const _RegionMenuButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Container(
        height: 40,
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

class _OfficialRouteMapAsset {
  const _OfficialRouteMapAsset({
    required this.path,
    required this.width,
    required this.height,
    this.sourceWidth,
    this.sourceHeight,
  });

  final String path;
  final double width;
  final double height;
  final double? sourceWidth;
  final double? sourceHeight;
}

_OfficialRouteMapAsset? _officialRouteMapAsset(String region) {
  return switch (region) {
    '수도권' => const _OfficialRouteMapAsset(
      path: 'assets/datapacks/maps/seoul-official-cyberstation-map.png',
      width: 1525,
      height: 1000,
      sourceWidth: 1525,
      sourceHeight: 1000,
    ),
    '부산권' => const _OfficialRouteMapAsset(
      path: 'assets/datapacks/maps/busan-official-route-map.jpg',
      width: 1302,
      height: 817,
      sourceWidth: 1680,
      sourceHeight: 980,
    ),
    '광주권' => const _OfficialRouteMapAsset(
      path: 'assets/datapacks/maps/gwangju-official-cyberstation-map.png',
      width: 2172,
      height: 554,
      sourceWidth: 2172,
      sourceHeight: 554,
    ),
    '대구권' => const _OfficialRouteMapAsset(
      path: 'assets/datapacks/maps/daegu-official-route-map.png',
      width: 1264,
      height: 1205,
      sourceWidth: 1264,
      sourceHeight: 1205,
    ),
    '대전권' => const _OfficialRouteMapAsset(
      path: 'assets/datapacks/maps/daejeon-official-cyberstation-map.jpg',
      width: 975,
      height: 447,
      sourceWidth: 975,
      sourceHeight: 447,
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

class _NetworkMapCanvasState extends State<_NetworkMapCanvas> {
  final TransformationController _controller = TransformationController();
  String? _layoutKey;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linesById = {for (final line in widget.data.lines) line.id: line};
    final stationsById = <String, NetworkMapStation>{};
    final stationLinesById = <String, List<NetworkMapLine>>{};
    for (final station in widget.data.stations) {
      stationsById[_mapStationKey(station)] = station;
      stationsById.putIfAbsent(station.id, () => station);
      final line = linesById[station.lineId];
      if (line == null) {
        continue;
      }
      stationLinesById.putIfAbsent(station.id, () => []).add(line);
    }
    final mapAsset = _officialRouteMapAsset(widget.data.selectedRegion);
    final geometry = mapAsset == null
        ? _MapGeometry.fromStations(widget.data.stations)
        : _MapGeometry.fromOfficialAsset(widget.data.stations, mapAsset);

    return Container(
      key: const Key('networkMapSurface'),
      decoration: const BoxDecoration(color: Colors.white),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layoutKey =
              '${widget.data.selectedRegion}:${geometry.width}:${geometry.height}:${constraints.maxWidth}:${constraints.maxHeight}';
          if (_layoutKey != layoutKey) {
            _layoutKey = layoutKey;
            _controller.value = _initialMapTransform(geometry, constraints);
          }
          return InteractiveViewer(
            transformationController: _controller,
            constrained: false,
            minScale: 0.08,
            maxScale: 4.8,
            boundaryMargin: const EdgeInsets.all(220),
            child: SizedBox(
              width: geometry.width,
              height: geometry.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: mapAsset == null
                        ? CustomPaint(
                            key: const Key('networkMapPainter'),
                            painter: _NetworkMapPainter(
                              edges: widget.data.edges,
                              stationsById: stationsById,
                              linesById: linesById,
                              transferStationIds: {
                                for (final entry in stationLinesById.entries)
                                  if (entry.value.length > 1) entry.key,
                              },
                              origin: geometry.origin,
                            ),
                          )
                        : Image.asset(
                            mapAsset.path,
                            key: const Key('officialRouteMapImage'),
                            width: mapAsset.width,
                            height: mapAsset.height,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.high,
                          ),
                  ),
                  for (final station in widget.data.stations)
                    Positioned(
                      left: geometry.x(station) - 22,
                      top: geometry.y(station) - 22,
                      child: _StationHitTarget(
                        key: Key(
                          'networkMapStation-${station.id.replaceFirst('station-', '')}',
                        ),
                        station: station,
                        onTap: () => widget.onStationTap(
                          station,
                          stationLinesById[station.id] ?? const [],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Matrix4 _initialMapTransform(
  _MapGeometry geometry,
  BoxConstraints constraints,
) {
  final viewportWidth = constraints.hasBoundedWidth ? constraints.maxWidth : 0;
  final viewportHeight = constraints.hasBoundedHeight
      ? constraints.maxHeight
      : 0;
  if (viewportWidth <= 0 || viewportHeight <= 0) {
    return Matrix4.identity();
  }
  final bounds = geometry.initialBounds;
  final initialScale = math.max(
    viewportWidth / bounds.width,
    viewportHeight / bounds.height,
  );
  final dx =
      (viewportWidth - bounds.width * initialScale) / 2 -
      bounds.left * initialScale;
  final dy =
      (viewportHeight - bounds.height * initialScale) / 2 -
      bounds.top * initialScale;
  return Matrix4.identity()
    ..translateByDouble(dx, dy, 0, 1)
    ..scaleByDouble(initialScale, initialScale, 1, 1);
}

class _NetworkMapPainter extends CustomPainter {
  const _NetworkMapPainter({
    required this.edges,
    required this.stationsById,
    required this.linesById,
    required this.transferStationIds,
    required this.origin,
  });

  final List<NetworkMapEdge> edges;
  final Map<String, NetworkMapStation> stationsById;
  final Map<String, NetworkMapLine> linesById;
  final Set<String> transferStationIds;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(-origin.dx, -origin.dy);
    final paintedPaths = <String>{};
    for (final station in stationsById.values) {
      final line = linesById[station.lineId];
      final paint = Paint()
        ..color = _colorFromHex(line?.color ?? '#006D77')
        ..style = PaintingStyle.stroke
        ..strokeWidth = _isSeoulMetroCyberStationSource(station) ? 3 : 8
        ..strokeCap = StrokeCap.round;
      for (final pathData in [
        station.position.upPath,
        station.position.downPath,
      ]) {
        if (pathData.isEmpty ||
            !paintedPaths.add('${station.lineId}:$pathData')) {
          continue;
        }
        canvas.drawPath(_pathFromSvg(pathData), paint);
      }
    }
    final paintedStations = <String>{};
    for (final station in stationsById.values) {
      if (!paintedStations.add(station.id)) {
        continue;
      }
      _drawStation(canvas, station);
    }
    canvas.restore();
  }

  void _drawStation(Canvas canvas, NetworkMapStation station) {
    final center = Offset(
      station.position.x.toDouble(),
      station.position.y.toDouble(),
    );
    final line = linesById[station.lineId];
    final color = _colorFromHex(line?.color ?? '#006D77');
    final transfer = transferStationIds.contains(station.id);
    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = transfer ? const Color(0xFF1C2F33) : color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _isSeoulMetroCyberStationSource(station)
          ? 1.2
          : (transfer ? 3.2 : 2.6);
    final radius = _isSeoulMetroCyberStationSource(station)
        ? 3.4
        : (transfer ? 8.5 : 6.2);
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius, stroke);

    final labelOffset = _labelOffsetFor(station);
    final textPainter = TextPainter(
      text: TextSpan(
        text: station.nameKo,
        style: TextStyle(
          color: const Color(0xFF102A2C),
          fontSize: _isSeoulMetroCyberStationSource(station)
              ? 5.6
              : (transfer ? 8.6 : 8),
          fontWeight: _isSeoulMetroCyberStationSource(station)
              ? FontWeight.w600
              : (transfer ? FontWeight.w800 : FontWeight.w700),
          height: 1,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _isSeoulMetroCyberStationSource(station) ? 52 : 58);
    final drawOffset = _labelDrawOffset(center, labelOffset, textPainter.size);
    textPainter.paint(canvas, drawOffset);
  }

  @override
  bool shouldRepaint(covariant _NetworkMapPainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.stationsById != stationsById ||
        oldDelegate.linesById != linesById ||
        oldDelegate.transferStationIds != transferStationIds ||
        oldDelegate.origin != origin;
  }
}

class _MapGeometry {
  _MapGeometry({
    required this.origin,
    required this.focus,
    required this.width,
    required this.height,
    Rect? initialBounds,
    this.scaleX = 1,
    this.scaleY = 1,
  }) : initialBounds = initialBounds ?? Rect.fromLTWH(0, 0, width, height);

  final Offset origin;
  final Offset focus;
  final double width;
  final double height;
  final Rect initialBounds;
  final double scaleX;
  final double scaleY;

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
    return _MapGeometry(
      origin: origin,
      focus: Offset(
        _median(stationXs) - origin.dx,
        _median(stationYs) - origin.dy,
      ),
      width: math.max(860, maxX - minX + margin * 2),
      height: math.max(560, maxY - minY + margin * 2),
    );
  }

  factory _MapGeometry.fromOfficialAsset(
    List<NetworkMapStation> stations,
    _OfficialRouteMapAsset asset,
  ) {
    if (asset.sourceWidth != null && asset.sourceHeight != null) {
      final scaleX = asset.width / asset.sourceWidth!;
      final scaleY = asset.height / asset.sourceHeight!;
      var minX = double.infinity;
      var minY = double.infinity;
      var maxX = 0.0;
      var maxY = 0.0;
      for (final station in stations) {
        final x = station.position.x * scaleX;
        final y = station.position.y * scaleY;
        minX = math.min(minX, x);
        minY = math.min(minY, y);
        maxX = math.max(maxX, x);
        maxY = math.max(maxY, y);
      }
      return _MapGeometry(
        origin: Offset.zero,
        focus: Offset(asset.width / 2, asset.height / 2),
        width: asset.width,
        height: asset.height,
        initialBounds:
            minX.isFinite && minY.isFinite && maxX > minX && maxY > minY
            ? Rect.fromLTRB(minX, minY, maxX, maxY)
            : null,
        scaleX: scaleX,
        scaleY: scaleY,
      );
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = 0.0;
    var maxY = 0.0;
    for (final station in stations) {
      minX = math.min(minX, station.position.x.toDouble());
      minY = math.min(minY, station.position.y.toDouble());
      maxX = math.max(maxX, station.position.x.toDouble());
      maxY = math.max(maxY, station.position.y.toDouble());
    }
    if (!minX.isFinite || !minY.isFinite || maxX <= minX || maxY <= minY) {
      return _MapGeometry(
        origin: Offset.zero,
        focus: Offset(asset.width / 2, asset.height / 2),
        width: asset.width,
        height: asset.height,
      );
    }
    const sourceMargin = 24.0;
    final sourceWidth = maxX - minX + sourceMargin * 2;
    final sourceHeight = maxY - minY + sourceMargin * 2;
    return _MapGeometry(
      origin: Offset(minX - sourceMargin, minY - sourceMargin),
      focus: Offset(asset.width / 2, asset.height / 2),
      width: asset.width,
      height: asset.height,
      scaleX: asset.width / sourceWidth,
      scaleY: asset.height / sourceHeight,
    );
  }

  double x(NetworkMapStation station) =>
      (station.position.x - origin.dx) * scaleX;

  double y(NetworkMapStation station) =>
      (station.position.y - origin.dy) * scaleY;
}

double _median(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  values.sort();
  return values[values.length ~/ 2];
}

bool _isSeoulMetroCyberStationSource(NetworkMapStation station) {
  return station.position.sourceId == 'seoulmetro-cyberstation';
}

bool _usesOfficialRouteMapSource(NetworkMapStation station) {
  return station.position.sourceId.endsWith('-cyberstation');
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

Offset _labelDrawOffset(Offset center, Offset labelOffset, Size textSize) {
  final x = labelOffset.dx < 0
      ? center.dx + labelOffset.dx - textSize.width
      : labelOffset.dx == 0
      ? center.dx - textSize.width / 2
      : center.dx + labelOffset.dx;
  return Offset(x, center.dy + labelOffset.dy - textSize.height / 2);
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox(width: 48, height: 48),
      ),
    );
  }
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
