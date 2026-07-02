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
import 'mobile_error_reporter.dart';
import 'station_search.dart';

const _networkMapTopBarHeight = 60.0;
const _networkMapBottomAdHeight = 52.0;
const _networkMapPillRadius = BorderRadius.all(Radius.circular(28));
const _networkMapSearchFieldRadius = BorderRadius.all(Radius.circular(12));
const _networkMapSearchFieldBorderColor = Color(0xFFDBE3E9);
const _networkMapSearchFieldHintColor = Color(0xFF466467);
const _networkMapSearchFieldIconColor = Color(0xFF8A9AA0);
const _networkMapMenuIconColor = Color(0xFF466467);
const _networkMapMenuLabelColor = Color(0xFF1E3234);
const _networkMapMenuSectionColor = Color(0xFF7C949A);
const _networkMapMenuChevronColor = Color(0xFFB0BEC5);

abstract interface class NetworkMapRepository {
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId});
}

abstract interface class NetworkMapViewportRepository {
  Future<Rect?> loadViewport(String region);

  Future<void> saveViewport({required String region, required Rect viewport});
}

class _NetworkMapLoadResult {
  const _NetworkMapLoadResult({
    required this.data,
    required this.initialViewport,
  });

  final NetworkMapData data;
  final Rect? initialViewport;
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
    this.stationSearchRepository,
    this.locationProvider,
    this.viewportRepository,
    this.onOpenSavedItems,
    this.onOpenRecentSearch,
    this.onOpenNearbyStations,
    this.notificationAction,
    this.bottomNavigationBar,
    super.key,
  });

  final NetworkMapRepository repository;
  final RouteDraftController routeDraftController;
  final Future<void> Function() onOpenRouteSearch;
  final VoidCallback onOpenStationSearch;
  final StationSearchRepository? stationSearchRepository;
  final CurrentLocationProvider? locationProvider;
  final NetworkMapViewportRepository? viewportRepository;
  final VoidCallback? onOpenSavedItems;
  final VoidCallback? onOpenRecentSearch;
  final VoidCallback? onOpenNearbyStations;
  final Widget? notificationAction;
  final Widget? bottomNavigationBar;

  @override
  State<NetworkMapScreen> createState() => _NetworkMapScreenState();
}

class _NetworkMapScreenState extends State<NetworkMapScreen> {
  String? _selectedRegion;
  bool _expressView = false;
  bool _nearbyPanelVisible = false;
  _NetworkMapNearbyPanelData _nearbyPanelData =
      const _NetworkMapNearbyPanelData.idle();
  String? _nearbySelectedStationId;
  String? _nearbyLookupMessage;
  Timer? _nearbyLookupMessageTimer;
  bool _initialNearbyFocusStarted = false;
  late Future<_NetworkMapLoadResult> _future = _loadMap();

  @override
  void dispose() {
    _nearbyLookupMessageTimer?.cancel();
    super.dispose();
  }

  Future<_NetworkMapLoadResult> _loadMap() async {
    final data = await widget.repository.getNetworkMap(region: _selectedRegion);
    final viewport = await widget.viewportRepository?.loadViewport(
      _displayRegionName(data.selectedRegion),
    );
    return _NetworkMapLoadResult(data: data, initialViewport: viewport);
  }

  void _reload({String? region}) {
    setState(() {
      _selectedRegion = region ?? _selectedRegion;
      _nearbySelectedStationId = null;
      _nearbyPanelVisible = false;
      _nearbyPanelData = const _NetworkMapNearbyPanelData.idle();
      _initialNearbyFocusStarted = false;
      _future = _loadMap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('networkMapScreen'),
      backgroundColor: const Color(0xFFFFFAFD),
      body: FutureBuilder<_NetworkMapLoadResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _NetworkMapChrome(
              regions: const [NetworkMapRegion(name: '수도권')],
              selectedRegion: _selectedRegion ?? '수도권',
              expressView: _expressView,
              showServicePatternToggle: true,
              notificationAction: widget.notificationAction,
              onMenuTap: _openMapMenu,
              onSearchTap: widget.onOpenStationSearch,
              onRegionSelected: (region) => _reload(region: region),
              onExpressViewChanged: (value) {
                setState(() => _expressView = value);
              },
              nearbyPanelVisible: _nearbyPanelVisible,
              nearbyPanelData: _nearbyPanelData,
              nearbyLookupMessage: _nearbyLookupMessage,
              adjacentStations: const _NetworkMapAdjacentStations(),
              onCurrentLocationTap: _showNearbyPanel,
              onOpenNearbyStations: widget.onOpenNearbyStations,
              onCloseNearbyPanel: _hideNearbyPanel,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _NetworkMapChrome(
              regions: const [NetworkMapRegion(name: '수도권')],
              selectedRegion: _selectedRegion ?? '수도권',
              expressView: _expressView,
              showServicePatternToggle: true,
              notificationAction: widget.notificationAction,
              onMenuTap: _openMapMenu,
              onSearchTap: widget.onOpenStationSearch,
              onRegionSelected: (region) => _reload(region: region),
              onExpressViewChanged: (value) {
                setState(() => _expressView = value);
              },
              nearbyPanelVisible: _nearbyPanelVisible,
              nearbyPanelData: _nearbyPanelData,
              nearbyLookupMessage: _nearbyLookupMessage,
              adjacentStations: const _NetworkMapAdjacentStations(),
              onCurrentLocationTap: _showNearbyPanel,
              onOpenNearbyStations: widget.onOpenNearbyStations,
              onCloseNearbyPanel: _hideNearbyPanel,
              child: _NetworkMapLoadFailure(onRetry: () => _reload()),
            );
          }
          final loadResult = snapshot.data!;
          final data = loadResult.data;
          final hasExpressLines = _expressLineIds(data).isNotEmpty;
          final hasAssetRenderer =
              _routeMapAssetForRegion(data.selectedRegion) != null;
          final visibleData =
              hasExpressLines && !hasAssetRenderer && _expressView
              ? _expressOnlyMapData(data)
              : data;
          _startInitialNearbyFocus();
          return _NetworkMapChrome(
            regions: data.regions,
            selectedRegion: data.selectedRegion,
            expressView: _expressView,
            showServicePatternToggle: !hasAssetRenderer,
            notificationAction: widget.notificationAction,
            onMenuTap: _openMapMenu,
            onSearchTap: widget.onOpenStationSearch,
            onRegionSelected: (region) => _reload(region: region),
            onExpressViewChanged: (value) {
              setState(() => _expressView = value);
            },
            nearbyPanelVisible: _nearbyPanelVisible,
            nearbyPanelData: _nearbyPanelData,
            nearbyLookupMessage: _nearbyLookupMessage,
            adjacentStations: _adjacentStationsFor(data),
            onCurrentLocationTap: _showNearbyPanel,
            onOpenNearbyStations: widget.onOpenNearbyStations,
            onCloseNearbyPanel: _hideNearbyPanel,
            child: _NetworkMapCanvas(
              data: visibleData,
              initialViewport: loadResult.initialViewport,
              focusedStationId: _nearbySelectedStationId,
              selectedStationId: _nearbyPanelVisible
                  ? _nearbySelectedStationId
                  : null,
              onSetOrigin: _setOriginStation,
              onSetDestination: _setDestinationStation,
              onOpenRouteSearch: _openRouteSearchFromMap,
              onViewportChanged: (viewport) {
                _saveRecentViewport(data.selectedRegion, viewport);
              },
            ),
          );
        },
      ),
      bottomNavigationBar: _nearbyPanelVisible
          ? null
          : const _NetworkMapBottomAdBanner(),
    );
  }

  Future<void> _showNearbyPanel() async {
    if (_nearbyPanelData.status == _NetworkMapNearbyPanelStatus.loading) {
      return;
    }
    setState(() {
      _nearbySelectedStationId = null;
      _nearbyPanelVisible = false;
      _nearbyPanelData = const _NetworkMapNearbyPanelData.loading();
    });
    final locationProvider = widget.locationProvider;
    final stationRepository = widget.stationSearchRepository;
    if (locationProvider == null || stationRepository == null) {
      if (!mounted) {
        return;
      }
      _showNearbyLookupMessage('현재 위치를 확인하지 못했어요.');
      return;
    }
    try {
      final location = await locationProvider.currentLocation();
      final blockedMessage = location.nearbySearchBlockedMessage();
      if (blockedMessage != null) {
        if (!mounted) {
          return;
        }
        _showNearbyLookupMessage(blockedMessage);
        return;
      }
      final results = await stationRepository.searchNearbyStations(
        location,
        limit: 4,
      );
      if (!mounted) {
        return;
      }
      if (results.isEmpty) {
        _showNearbyLookupMessage('주변 역을 찾지 못했어요.');
        return;
      }
      setState(() {
        _nearbyPanelVisible = true;
        _nearbySelectedStationId = results.first.id;
        _nearbyPanelData = _NetworkMapNearbyPanelData.success(results);
      });
    } on CurrentLocationException catch (error) {
      if (!mounted) {
        return;
      }
      _showNearbyLookupMessage(error.message);
    } on StationSearchException catch (error) {
      if (!mounted) {
        return;
      }
      _showNearbyLookupMessage(error.message);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 주변 역 확인 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      _showNearbyLookupMessage('주변 역을 불러오지 못했어요.');
    }
  }

  void _showNearbyLookupMessage(String message) {
    _nearbyLookupMessageTimer?.cancel();
    setState(() {
      _nearbyPanelVisible = false;
      _nearbySelectedStationId = null;
      _nearbyPanelData = const _NetworkMapNearbyPanelData.idle();
      _nearbyLookupMessage = message;
    });
    _nearbyLookupMessageTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) {
        return;
      }
      setState(() => _nearbyLookupMessage = null);
    });
  }

  void _startInitialNearbyFocus() {
    if (_initialNearbyFocusStarted ||
        _nearbySelectedStationId != null ||
        _nearbyPanelVisible) {
      return;
    }
    if (widget.viewportRepository == null) {
      return;
    }
    final locationProvider = widget.locationProvider;
    final stationRepository = widget.stationSearchRepository;
    if (locationProvider == null || stationRepository == null) {
      return;
    }
    _initialNearbyFocusStarted = true;
    unawaited(_focusInitialNearbyStation(locationProvider, stationRepository));
  }

  Future<void> _focusInitialNearbyStation(
    CurrentLocationProvider locationProvider,
    StationSearchRepository stationRepository,
  ) async {
    try {
      if (await locationProvider.needsLocationPermissionRequest()) {
        return;
      }
      final location = await locationProvider.currentLocation();
      if (location.nearbySearchBlockedMessage() != null) {
        return;
      }
      final results = await stationRepository.searchNearbyStations(
        location,
        limit: 1,
      );
      if (!mounted || results.isEmpty || _nearbyPanelVisible) {
        return;
      }
      setState(() {
        _nearbySelectedStationId = results.first.id;
      });
    } on CurrentLocationException {
      return;
    } on StationSearchException {
      return;
    }
  }

  void _saveRecentViewport(String region, Rect viewport) {
    final repository = widget.viewportRepository;
    if (repository == null) {
      return;
    }
    unawaited(
      repository
          .saveViewport(region: _displayRegionName(region), viewport: viewport)
          .catchError((Object error, StackTrace stackTrace) {
            reportMobileError(
              error,
              stackTrace,
              context: '노선도 최근 화면 위치 저장 중 예외가 발생했습니다.',
            );
          }),
    );
  }

  void _hideNearbyPanel() {
    setState(() {
      _nearbyPanelVisible = false;
      _nearbySelectedStationId = null;
      _nearbyPanelData = const _NetworkMapNearbyPanelData.idle();
    });
  }

  Future<void> _openMapMenu() {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '메뉴 닫기',
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _NetworkMapMenuPanel(
          onOpenStationSearch: widget.onOpenStationSearch,
          onOpenRouteSearch: widget.onOpenRouteSearch,
          onOpenSavedItems: widget.onOpenSavedItems,
          onOpenNearbyStations: widget.onOpenNearbyStations,
          onOpenRecentSearch: widget.onOpenRecentSearch,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        );
      },
    );
  }

  void _setOriginStation(NetworkMapStation station) {
    widget.routeDraftController.setOrigin(
      RouteDraftStation(id: station.id, nameKo: station.nameKo),
    );
  }

  void _setDestinationStation(NetworkMapStation station) {
    widget.routeDraftController.setDestination(
      RouteDraftStation(id: station.id, nameKo: station.nameKo),
    );
  }

  void _openRouteSearchFromMap(NetworkMapStation station) {
    widget.onOpenRouteSearch();
  }

  _NetworkMapAdjacentStations _adjacentStationsFor(NetworkMapData data) {
    final selectedStationId = _nearbySelectedStationId;
    if (selectedStationId == null) {
      return const _NetworkMapAdjacentStations();
    }
    final primaryResult = _nearbyPanelData.results.isEmpty
        ? null
        : _nearbyPanelData.results.first;
    final primaryLineId = primaryResult == null || primaryResult.lines.isEmpty
        ? null
        : primaryResult.lines.first.id;
    final selectedStations = data.stations
        .where((station) => station.id == selectedStationId)
        .toList(growable: false);
    if (selectedStations.isEmpty) {
      return const _NetworkMapAdjacentStations();
    }
    final selectedStation = selectedStations.firstWhere(
      (station) => station.lineId == primaryLineId,
      orElse: () => selectedStations.first,
    );
    NetworkMapStation? left;
    NetworkMapStation? right;
    for (final edge in data.edges) {
      if (edge.lineId != selectedStation.lineId) {
        continue;
      }
      final from = networkMapStationForMapEdgeEndpoint(
        endpoint: edge.fromStationId,
        lineId: edge.lineId,
        stations: data.stations,
      );
      final to = networkMapStationForMapEdgeEndpoint(
        endpoint: edge.toStationId,
        lineId: edge.lineId,
        stations: data.stations,
      );
      NetworkMapStation? candidate;
      if (_sameMapStation(from, selectedStation)) {
        candidate = to;
      } else if (_sameMapStation(to, selectedStation)) {
        candidate = from;
      }
      if (candidate == null) {
        continue;
      }
      if (candidate.sequence < selectedStation.sequence) {
        if (left == null || candidate.sequence > left.sequence) {
          left = candidate;
        }
      } else if (candidate.sequence > selectedStation.sequence) {
        if (right == null || candidate.sequence < right.sequence) {
          right = candidate;
        }
      }
    }
    return _NetworkMapAdjacentStations(
      leftName: left?.nameKo,
      rightName: right?.nameKo,
    );
  }
}

bool _sameMapStation(NetworkMapStation? a, NetworkMapStation b) {
  return a != null && a.id == b.id && a.lineId == b.lineId;
}

class _NetworkMapChrome extends StatelessWidget {
  const _NetworkMapChrome({
    required this.regions,
    required this.selectedRegion,
    required this.expressView,
    required this.showServicePatternToggle,
    required this.notificationAction,
    required this.onMenuTap,
    required this.onSearchTap,
    required this.onRegionSelected,
    required this.onExpressViewChanged,
    required this.nearbyPanelVisible,
    required this.nearbyPanelData,
    required this.nearbyLookupMessage,
    required this.adjacentStations,
    required this.onCurrentLocationTap,
    required this.onOpenNearbyStations,
    required this.onCloseNearbyPanel,
    required this.child,
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final bool expressView;
  final bool showServicePatternToggle;
  final Widget? notificationAction;
  final VoidCallback onMenuTap;
  final VoidCallback onSearchTap;
  final ValueChanged<String> onRegionSelected;
  final ValueChanged<bool> onExpressViewChanged;
  final bool nearbyPanelVisible;
  final _NetworkMapNearbyPanelData nearbyPanelData;
  final String? nearbyLookupMessage;
  final _NetworkMapAdjacentStations adjacentStations;
  final VoidCallback onCurrentLocationTap;
  final VoidCallback? onOpenNearbyStations;
  final VoidCallback onCloseNearbyPanel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(
          top: topPadding + _networkMapTopBarHeight,
          child: ClipRect(child: child),
        ),
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          child: _NetworkMapTopBar(
            regions: regions,
            selectedRegion: selectedRegion,
            notificationAction: notificationAction,
            onMenuTap: onMenuTap,
            onSearchTap: onSearchTap,
            onRegionSelected: onRegionSelected,
          ),
        ),
        if (showServicePatternToggle)
          Positioned(
            left: 16,
            bottom: 26,
            child: _NetworkMapServicePatternToggle(
              expressView: expressView,
              onChanged: onExpressViewChanged,
            ),
          ),
        if (nearbyPanelVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _NetworkMapNearbyStationPanel(
              data: nearbyPanelData,
              adjacentStations: adjacentStations,
              onClose: onCloseNearbyPanel,
              onRetry: onCurrentLocationTap,
            ),
          ),
        if (nearbyLookupMessage != null)
          Positioned(
            left: 24,
            right: 24,
            bottom: nearbyPanelVisible ? 318 : 132,
            child: _NetworkMapLookupToast(message: nearbyLookupMessage!),
          ),
        if (onOpenNearbyStations != null)
          Positioned(
            right: 16,
            bottom: nearbyPanelVisible ? 280 : 26,
            child: _NetworkMapCurrentLocationButton(
              onTap: onCurrentLocationTap,
            ),
          ),
      ],
    );
  }
}

class _NetworkMapLookupToast extends StatelessWidget {
  const _NetworkMapLookupToast({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Material(
        key: const Key('networkMapNearbyLookupMessage'),
        color: const Color(0xE62F3437),
        elevation: 10,
        shadowColor: const Color(0x33000000),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkMapTopBar extends StatelessWidget {
  const _NetworkMapTopBar({
    required this.regions,
    required this.selectedRegion,
    required this.notificationAction,
    required this.onMenuTap,
    required this.onSearchTap,
    required this.onRegionSelected,
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final Widget? notificationAction;
  final VoidCallback onMenuTap;
  final VoidCallback onSearchTap;
  final ValueChanged<String> onRegionSelected;

  @override
  Widget build(BuildContext context) {
    final currentRegion = _displayRegionName(selectedRegion);
    final availableRegions = regions.isEmpty
        ? const [NetworkMapRegion(name: '수도권')]
        : regions;
    return Material(
      color: EasySubwayAccessibleColors.surface,
      elevation: 4,
      shadowColor: const Color(0x26000000),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: _networkMapTopBarHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Row(
              children: [
                IconButton(
                  key: const Key('networkMapMenuButton'),
                  tooltip: '메뉴',
                  onPressed: onMenuTap,
                  style: IconButton.styleFrom(
                    minimumSize: const Size.square(
                      EasySubwayTouchTarget.general,
                    ),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(
                    Icons.menu,
                    size: 22,
                    color: Color(0xFF4B4B4B),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _NetworkMapSearchField(onSearchTap: onSearchTap),
                ),
                const SizedBox(width: 8),
                Semantics(
                  key: const Key('mapRegionTabs'),
                  container: true,
                  button: true,
                  label: '지역: $currentRegion',
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 84),
                    child: SizedBox(
                      height: EasySubwayTouchTarget.general,
                      child: ExcludeSemantics(
                        child: InkWell(
                          key: const Key('networkMapRegionDropdown'),
                          onTap: () =>
                              _showRegionSheet(context, availableRegions),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  currentRegion,
                                  style: const TextStyle(
                                    color: Color(0xFF606060),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  color: Color(0xFF606060),
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (notificationAction != null) ...[
                  const SizedBox(width: 8),
                  notificationAction!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRegionSheet(
    BuildContext context,
    List<NetworkMapRegion> availableRegions,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            key: const Key('networkMapRegionSheet'),
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text(
                '지역 선택',
                style: TextStyle(
                  color: _networkMapMenuLabelColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              for (final region in availableRegions)
                _NetworkMapRegionRow(
                  label: region.displayName,
                  selected: region.name == selectedRegion,
                  onTap: () => Navigator.of(context).pop(region.name),
                ),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      onRegionSelected(selected);
    }
  }
}

class _NetworkMapRegionRow extends StatelessWidget {
  const _NetworkMapRegionRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label 지역 ${selected ? '선택됨' : '선택 안 됨'}',
      button: true,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: EasySubwayAccessibleColors.line),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? EasySubwayAccessibleColors.primary
                          : _networkMapMenuLabelColor,
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check,
                    size: 22,
                    color: EasySubwayAccessibleColors.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkMapSearchField extends StatelessWidget {
  const _NetworkMapSearchField({required this.onSearchTap});

  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '지하철역 검색',
      onTap: onSearchTap,
      child: ExcludeSemantics(
        child: InkWell(
          key: const Key('stationSearchButton'),
          onTap: onSearchTap,
          borderRadius: _networkMapSearchFieldRadius,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 72;
              return SizedBox(
                height: EasySubwayTouchTarget.general,
                child: Center(
                  child: Container(
                    key: const Key('heroStationSearchButton'),
                    height: 38,
                    decoration: BoxDecoration(
                      color: EasySubwayAccessibleColors.surface,
                      border: Border.all(
                        color: _networkMapSearchFieldBorderColor,
                        width: 1.5,
                      ),
                      borderRadius: _networkMapSearchFieldRadius,
                    ),
                    padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
                    child: compact
                        ? const SizedBox.shrink()
                        : const Row(
                            children: [
                              Icon(
                                Icons.search,
                                size: 18,
                                color: _networkMapSearchFieldIconColor,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '지하철역 검색',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _networkMapSearchFieldHintColor,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NetworkMapServicePatternToggle extends StatelessWidget {
  const _NetworkMapServicePatternToggle({
    required this.expressView,
    required this.onChanged,
  });

  final bool expressView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('networkMapServicePatternToggle'),
      color: Colors.white,
      elevation: 16,
      shadowColor: const Color(0x30000000),
      borderRadius: _networkMapPillRadius,
      child: Container(
        height: 58,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: _networkMapPillRadius,
          border: Border.all(color: const Color(0xFFE8E8E8)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NetworkMapToggleSegment(
              label: '일반',
              selected: !expressView,
              onTap: () => onChanged(false),
            ),
            _NetworkMapToggleSegment(
              label: '급행',
              selected: expressView,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _NetworkMapCurrentLocationButton extends StatelessWidget {
  const _NetworkMapCurrentLocationButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '현재 위치로 주변 역 찾기',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          key: const Key('nearbyStationButton'),
          color: Colors.white,
          elevation: 14,
          shadowColor: const Color(0x26000000),
          shape: const CircleBorder(
            side: BorderSide(color: Color(0xFFD8D8D8), width: 1),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                Icons.my_location,
                size: 27,
                color: Color(0xFF565656),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _NetworkMapNearbyPanelStatus { idle, loading, success }

class _NetworkMapNearbyPanelData {
  const _NetworkMapNearbyPanelData._({
    required this.status,
    this.results = const [],
  });

  const _NetworkMapNearbyPanelData.idle()
    : this._(status: _NetworkMapNearbyPanelStatus.idle);

  const _NetworkMapNearbyPanelData.loading()
    : this._(status: _NetworkMapNearbyPanelStatus.loading);

  const _NetworkMapNearbyPanelData.success(List<StationSearchResult> results)
    : this._(status: _NetworkMapNearbyPanelStatus.success, results: results);

  final _NetworkMapNearbyPanelStatus status;
  final List<StationSearchResult> results;
}

class _NetworkMapAdjacentStations {
  const _NetworkMapAdjacentStations({this.leftName, this.rightName});

  final String? leftName;
  final String? rightName;
}

class _NetworkMapNearbyStationPanel extends StatelessWidget {
  const _NetworkMapNearbyStationPanel({
    required this.data,
    required this.adjacentStations,
    required this.onClose,
    required this.onRetry,
  });

  final _NetworkMapNearbyPanelData data;
  final _NetworkMapAdjacentStations adjacentStations;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final primary = data.results.isEmpty ? null : data.results.first;
    final primaryLine = primary == null || primary.lines.isEmpty
        ? null
        : primary.lines.first;
    return Material(
      key: const Key('networkMapNearbyStationPanel'),
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFD8D8D8))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 14),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: _SubwayLinePanelTab(line: primaryLine),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        height: 24,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFFFCACA)),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          '실시간',
                          style: TextStyle(
                            color: Color(0xFFFF7777),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: IconButton(
                        tooltip: '다시 찾기',
                        onPressed: onRetry,
                        constraints: const BoxConstraints.tightFor(
                          width: 38,
                          height: 38,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.refresh,
                          color: Color(0xFF5A5A5A),
                          size: 27,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: IconButton(
                        key: const Key('networkMapNearbyPanelCloseButton'),
                        tooltip: '닫기',
                        onPressed: onClose,
                        constraints: const BoxConstraints.tightFor(
                          width: 38,
                          height: 38,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.close,
                          color: Color(0xFF454545),
                          size: 27,
                        ),
                      ),
                    ),
                    const SizedBox(width: 22),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFD8D8D8)),
              _NetworkMapNearbyPanelBody(
                data: data,
                adjacentStations: adjacentStations,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NetworkMapNearbyPanelBody extends StatelessWidget {
  const _NetworkMapNearbyPanelBody({
    required this.data,
    required this.adjacentStations,
  });

  final _NetworkMapNearbyPanelData data;
  final _NetworkMapAdjacentStations adjacentStations;

  @override
  Widget build(BuildContext context) {
    return switch (data.status) {
      _NetworkMapNearbyPanelStatus.idle ||
      _NetworkMapNearbyPanelStatus.loading => const SizedBox(
        height: 132,
        child: Center(child: CircularProgressIndicator()),
      ),
      _NetworkMapNearbyPanelStatus.success => _NetworkMapNearbySuccessList(
        results: data.results,
        adjacentStations: adjacentStations,
      ),
    };
  }
}

class _NetworkMapNearbySuccessList extends StatelessWidget {
  const _NetworkMapNearbySuccessList({
    required this.results,
    required this.adjacentStations,
  });

  final List<StationSearchResult> results;
  final _NetworkMapAdjacentStations adjacentStations;

  @override
  Widget build(BuildContext context) {
    final primary = results.first;
    final leftName = adjacentStations.leftName ?? '-';
    final rightName = adjacentStations.rightName ?? '-';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 18, 13, 0),
          child: Container(
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF13B8D6),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '< $leftName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 126),
                  height: 34,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF13B8D6),
                      width: 3,
                    ),
                  ),
                  child: Text(
                    primary.nameKo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF2C2C2C),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '$rightName >',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 17),
        Padding(
          padding: const EdgeInsets.fromLTRB(42, 0, 42, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SubwayArrivalColumn(
                  arrivals: const [_SubwayArrivalPlaceholder()],
                ),
              ),
              const SizedBox(
                height: 46,
                child: VerticalDivider(color: Color(0xFFE0E0E0), width: 30),
              ),
              Expanded(
                child: _SubwayArrivalColumn(
                  arrivals: const [_SubwayArrivalPlaceholder()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubwayLinePanelTab extends StatelessWidget {
  const _SubwayLinePanelTab({required this.line});

  final StationSearchLine? line;

  @override
  Widget build(BuildContext context) {
    final label = line?.badgeText ?? '';
    return SizedBox(
      width: 36,
      height: 33,
      child: Column(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: line?.badgeColor ?? const Color(0xFF8D8D8D),
              shape: BoxShape.circle,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
          Container(width: 30, height: 2, color: const Color(0xFF5A5A5A)),
        ],
      ),
    );
  }
}

class _SubwayArrivalPlaceholder {
  const _SubwayArrivalPlaceholder();
}

class _SubwayArrivalColumn extends StatelessWidget {
  const _SubwayArrivalColumn({required this.arrivals});

  final List<_SubwayArrivalPlaceholder> arrivals;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: arrivals
          .map((arrival) => const _SubwayArrivalRow())
          .toList(growable: false),
    );
  }
}

class _SubwayArrivalRow extends StatelessWidget {
  const _SubwayArrivalRow();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 2),
      child: Center(
        child: Text(
          '-',
          style: TextStyle(
            color: Color(0xFF2F2F2F),
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _NetworkMapToggleSegment extends StatelessWidget {
  const _NetworkMapToggleSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: _networkMapPillRadius,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 52,
        width: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF006FD6) : Colors.transparent,
          borderRadius: _networkMapPillRadius,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF242424),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _NetworkMapBottomAdBanner extends StatelessWidget {
  const _NetworkMapBottomAdBanner();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('networkMapBottomAdBanner'),
        height: _networkMapBottomAdHeight,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E5E5))),
        ),
        child: const Text(
          '광고',
          style: TextStyle(
            color: Color(0xFF666666),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _NetworkMapMenuPanel extends StatelessWidget {
  const _NetworkMapMenuPanel({
    required this.onOpenStationSearch,
    required this.onOpenRouteSearch,
    required this.onOpenSavedItems,
    required this.onOpenNearbyStations,
    required this.onOpenRecentSearch,
  });

  final VoidCallback onOpenStationSearch;
  final Future<void> Function() onOpenRouteSearch;
  final VoidCallback? onOpenSavedItems;
  final VoidCallback? onOpenNearbyStations;
  final VoidCallback? onOpenRecentSearch;

  void _runAction(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  void _runFutureAction(BuildContext context, Future<void> Function() action) {
    Navigator.of(context).pop();
    unawaited(action());
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.625;
    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        key: const Key('networkMapMenuPanel'),
        color: Colors.white,
        child: SizedBox(
          width: width.clamp(280.0, 430.0).toDouble(),
          height: double.infinity,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _NetworkMapMenuHeader(),
                const Divider(height: 1, color: Color(0xFFE4E4E4)),
                const _NetworkMapMenuSectionLabel('탐색'),
                _NetworkMapMenuTile(
                  key: const Key('networkMapMenuStationSearchButton'),
                  icon: Icons.search,
                  label: '역 검색',
                  onTap: () => _runAction(context, onOpenStationSearch),
                ),
                _NetworkMapMenuTile(
                  key: const Key('networkMapMenuRouteSearchButton'),
                  icon: Icons.route_outlined,
                  label: '길찾기',
                  onTap: () => _runFutureAction(context, onOpenRouteSearch),
                ),
                if (onOpenNearbyStations != null)
                  _NetworkMapMenuTile(
                    key: const Key('networkMapMenuNearbyButton'),
                    icon: Icons.near_me_outlined,
                    label: '가까운 역',
                    onTap: () => _runAction(context, onOpenNearbyStations!),
                  ),
                if (onOpenRecentSearch != null)
                  _NetworkMapMenuTile(
                    key: const Key('networkMapMenuRecentButton'),
                    icon: Icons.history,
                    label: '최근 검색',
                    onTap: () => _runAction(context, onOpenRecentSearch!),
                  ),
                if (onOpenSavedItems != null) ...[
                  const _NetworkMapMenuSectionLabel('내 정보'),
                  _NetworkMapMenuTile(
                    key: const Key('networkMapMenuSavedButton'),
                    icon: Icons.star_border_rounded,
                    label: '즐겨찾기',
                    onTap: () => _runAction(context, onOpenSavedItems!),
                  ),
                ],
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFFEDEDED)),
                const _NetworkMapMenuInfoBanner(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 6, 24, 8),
                  child: Text(
                    '교통약자 이동을 더 쉽게',
                    style: TextStyle(
                      color: Color(0xFF9A9A9A),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkMapMenuHeader extends StatelessWidget {
  const _NetworkMapMenuHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 14, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '쉬운 지하철',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _networkMapMenuLabelColor,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(height: 3),
          Text(
            '교통약자 지하철 길찾기',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _networkMapMenuSectionColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkMapMenuSectionLabel extends StatelessWidget {
  const _NetworkMapMenuSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _networkMapMenuSectionColor,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _NetworkMapMenuTile extends StatelessWidget {
  const _NetworkMapMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          highlightColor: const Color(0x14006D77),
          splashColor: const Color(0x14006D77),
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: _networkMapMenuIconColor),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _networkMapMenuLabelColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: _networkMapMenuChevronColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkMapMenuInfoBanner extends StatelessWidget {
  const _NetworkMapMenuInfoBanner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.elevator_outlined,
            size: 18,
            color: _networkMapMenuSectionColor,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '엘리베이터·출구 정보를 한 화면에서 확인할 수 있어요',
              style: TextStyle(
                color: _networkMapMenuSectionColor,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Set<String> _expressLineIds(NetworkMapData data) {
  return data.lines
      .where(
        (line) =>
            line.name.contains('급행') ||
            line.shortName.contains('급행') ||
            line.id.toLowerCase().contains('express'),
      )
      .map((line) => line.id)
      .toSet();
}

NetworkMapData _expressOnlyMapData(NetworkMapData data) {
  final lineIds = _expressLineIds(data);
  final stationIdsFromMemberships = data.stationLineMemberships
      .where((membership) => lineIds.contains(membership.lineId))
      .map((membership) => membership.stationId)
      .toSet();
  final stations = data.stations
      .where(
        (station) =>
            lineIds.contains(station.lineId) ||
            stationIdsFromMemberships.contains(station.id),
      )
      .toList(growable: false);
  final stationsById = <String, List<NetworkMapStation>>{};
  final stationByLineKey = <String, NetworkMapStation>{};
  for (final station in stations) {
    stationsById.putIfAbsent(station.id, () => []).add(station);
    stationByLineKey[_networkMapStationLineKey(station.id, station.lineId)] =
        station;
  }
  bool hasFilteredEndpoint(NetworkMapEdge edge, String endpoint) {
    return _stationForMapEdgeEndpoint(
          endpoint,
          edge.lineId,
          stationByLineKey,
          stationsById,
        ) !=
        null;
  }

  return NetworkMapData(
    regions: data.regions,
    selectedRegion: data.selectedRegion,
    lines: data.lines
        .where((line) => lineIds.contains(line.id))
        .toList(growable: false),
    stations: stations,
    edges: data.edges
        .where(
          (edge) =>
              lineIds.contains(edge.lineId) &&
              hasFilteredEndpoint(edge, edge.fromStationId) &&
              hasFilteredEndpoint(edge, edge.toStationId),
        )
        .toList(growable: false),
    positionSources: data.positionSources,
    stationLineMemberships: data.stationLineMemberships
        .where((membership) => lineIds.contains(membership.lineId))
        .toList(growable: false),
  );
}

@visibleForTesting
NetworkMapData networkMapExpressOnlyMapData(NetworkMapData data) {
  return _expressOnlyMapData(data);
}

class _NetworkMapLoadFailure extends StatelessWidget {
  const _NetworkMapLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: AccessibleStateCard(
          icon: Icons.map_outlined,
          title: '노선도를 불러오지 못했어요',
          subtitle: '네트워크 상태를 확인한 뒤 다시 시도하거나 역명으로 검색해 주세요.',
          actions: [
            FilledButton.icon(
              key: const Key('networkMapRetryButton'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
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
    required this.initialViewport,
    required this.focusedStationId,
    required this.selectedStationId,
    required this.onSetOrigin,
    required this.onSetDestination,
    required this.onOpenRouteSearch,
    required this.onViewportChanged,
  });

  final NetworkMapData data;
  final Rect? initialViewport;
  final String? focusedStationId;
  final String? selectedStationId;
  final ValueChanged<NetworkMapStation> onSetOrigin;
  final ValueChanged<NetworkMapStation> onSetDestination;
  final ValueChanged<NetworkMapStation> onOpenRouteSearch;
  final ValueChanged<Rect> onViewportChanged;

  @override
  State<_NetworkMapCanvas> createState() => _NetworkMapCanvasState();
}

const _minMapScale = 0.08;
const _maxMapScale = 4.8;
const _routeMapGestureRendererCommitInterval = Duration(milliseconds: 1100);
const _routeMapGestureMaxTranslationDriftFraction = 1.35;
const _routeMapGestureMaxScaleRatio = 3.4;
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
  String? _cameraFocusedStationId;
  MapCameraState? _gestureStartCamera;
  Offset? _gestureStartFocalPoint;
  RouteMapRendererHealthMonitor? _rendererMonitor;
  RouteMapRendererController? _rendererController;
  String? _geometryCacheKey;
  _MapGeometry? _geometryCache;
  NetworkMapStation? _selectedStation;

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
          final layoutKey =
              '${widget.data.selectedRegion}:${geometry.width}:${geometry.height}:${constraints.maxWidth}:${constraints.maxHeight}';
          if (_layoutKey != layoutKey) {
            _layoutKey = layoutKey;
            _pendingCamera = null;
            _requestedRendererCamera = null;
            _presentedRendererCamera = null;
            _requestedRendererCamerasByRevision.clear();
            _routeMapRendererActive = mapAsset != null;
            _lastRendererCameraRequestAt = null;
            _gestureActive = false;
            _cameraFocusedStationId = null;
            final initialCamera = _cameraForBounds(
              widget.initialViewport ?? geometry.initialBounds,
              constraints,
              sourceBounds: fullBounds,
              contain: true,
              minScale: minScale,
            );
            final initialRendererCamera = networkMapOverscannedRendererCamera(
              initialCamera,
            );
            _camera = initialCamera;
            if (_routeMapRendererActive) {
              _requestedRendererCamera = initialRendererCamera;
              _presentedRendererCamera = initialRendererCamera;
            }
          }
          var camera =
              _camera ??
              _cameraForBounds(
                geometry.initialBounds,
                constraints,
                sourceBounds: fullBounds,
                minScale: minScale,
              );
          final selectedStation =
              _stationByIdentity(widget.data.stations, _selectedStation) ??
              _stationById(widget.data.stations, widget.selectedStationId);
          final focusedStation = widget.focusedStationId == null
              ? null
              : _stationById(widget.data.stations, widget.focusedStationId);
          if (!_gestureActive &&
              focusedStation != null &&
              _cameraFocusedStationId != focusedStation.id) {
            final focusedCamera = _cameraForBounds(
              _stationFocusBoundsFor(focusedStation, geometry),
              constraints,
              sourceBounds: fullBounds,
              contain: true,
              minScale: minScale,
              revision: camera.revision + 1,
            );
            _cameraFocusedStationId = focusedStation.id;
            _pendingCamera = null;
            _camera = focusedCamera;
            camera = focusedCamera;
            widget.onViewportChanged(focusedCamera.visibleSourceRect);
            if (_routeMapRendererActive) {
              final rendererCamera = networkMapOverscannedRendererCamera(
                focusedCamera,
              );
              _requestedRendererCamera = rendererCamera;
              _presentedRendererCamera = rendererCamera;
            }
          } else if (focusedStation == null) {
            _cameraFocusedStationId = null;
          }
          return Stack(
            children: [
              Positioned.fill(
                child: mapAsset == null || !_routeMapRendererActive
                    ? const _OriginalRouteMapUnavailable()
                    : _RouteMapViewportRenderer(
                        asset: mapAsset,
                        camera:
                            _requestedRendererCamera ??
                            networkMapOverscannedRendererCamera(camera),
                        presentedCamera:
                            _presentedRendererCamera ??
                            _requestedRendererCamera ??
                            networkMapOverscannedRendererCamera(camera),
                        gestureActive: _gestureActive,
                        visualCamera: camera,
                        onControllerCreated: _attachRendererController,
                      ),
              ),
              Positioned.fill(
                child: Semantics(
                  label: '노선도',
                  hint: '역을 누르면 출발, 도착, 역 정보 action을 볼 수 있어요',
                  child: Listener(
                    onPointerCancel: (_) => _endScaleGesture(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onScaleStart: (details) {
                        if (!_gestureActive) {
                          setState(() {
                            _gestureActive = true;
                            _selectedStation = null;
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
                      onTap: () => _selectStation(station),
                    ),
                  ),
              if (!_gestureActive && selectedStation != null)
                _NetworkMapStationActionOverlay(
                  station: selectedStation,
                  geometry: geometry,
                  camera: camera,
                  onSetOrigin: () {
                    widget.onSetOrigin(selectedStation);
                  },
                  onSetDestination: () {
                    widget.onSetDestination(selectedStation);
                  },
                  onOpenRouteSearch: () {
                    widget.onOpenRouteSearch(selectedStation);
                  },
                  onClose: () => setState(() => _selectedStation = null),
                ),
            ],
          );
        },
      ),
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
    final pendingCamera = _pendingCamera;
    if (pendingCamera != null) {
      widget.onViewportChanged(pendingCamera.visibleSourceRect);
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
    _selectStation(station);
  }

  void _selectStation(NetworkMapStation station) {
    setState(() => _selectedStation = station);
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
    if (event is RouteMapRendererFailed) {
      _releaseRenderer(disposeRenderer: true);
      if (mounted) {
        setState(() {
          _routeMapRendererActive = false;
          _requestedRendererCamera = null;
          _presentedRendererCamera = null;
          _requestedRendererCamerasByRevision.clear();
        });
      }
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

class _RouteMapViewportRenderer extends StatelessWidget {
  const _RouteMapViewportRenderer({
    required this.asset,
    required this.camera,
    required this.presentedCamera,
    required this.gestureActive,
    required this.visualCamera,
    required this.onControllerCreated,
  });

  final _RouteMapAsset asset;
  final MapCameraState camera;
  final MapCameraState presentedCamera;
  final bool gestureActive;
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
    final rendererCamera = gestureActive ? camera : visualCamera;
    final renderer = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidRouteMapViewportWebView(
        assetPath: asset.path,
        mimeType: asset.mimeType,
        camera: rendererCamera,
        onControllerCreated: onControllerCreated,
      ),
      TargetPlatform.iOS => IosRouteMapViewportWebView(
        assetPath: asset.path,
        mimeType: asset.mimeType,
        camera: rendererCamera,
        onControllerCreated: onControllerCreated,
      ),
      _ => const ColoredBox(color: Colors.white),
    };
    return ClipRect(
      child: KeyedSubtree(
        key: const Key('routeMapViewportRenderer'),
        child: renderer,
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

@visibleForTesting
Rect networkMapInitialOriginalAssetBounds({
  required double sourceWidth,
  required double sourceHeight,
}) {
  final width = sourceWidth * 0.58;
  final height = sourceHeight * 0.58;
  return _sourceCenteredBounds(
    center: Offset(sourceWidth / 2, sourceHeight / 2),
    width: width,
    height: height,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
  );
}

Rect _stationFocusBoundsFor(NetworkMapStation station, _MapGeometry geometry) {
  final width = math.min(
    geometry.width,
    math.max(860.0, geometry.width * 0.28),
  );
  final height = math.min(
    geometry.height,
    math.max(860.0, geometry.height * 0.28),
  );
  return _sourceCenteredBounds(
    center: Offset(geometry.x(station), geometry.y(station)),
    width: width,
    height: height,
    sourceWidth: geometry.width,
    sourceHeight: geometry.height,
  );
}

Rect _sourceCenteredBounds({
  required Offset center,
  required double width,
  required double height,
  required double sourceWidth,
  required double sourceHeight,
}) {
  final clampedWidth = width.clamp(1.0, sourceWidth).toDouble();
  final clampedHeight = height.clamp(1.0, sourceHeight).toDouble();
  final maxLeft = math.max(0.0, sourceWidth - clampedWidth);
  final maxTop = math.max(0.0, sourceHeight - clampedHeight);
  final left = (center.dx - clampedWidth / 2).clamp(0.0, maxLeft).toDouble();
  final top = (center.dy - clampedHeight / 2).clamp(0.0, maxTop).toDouble();
  return Rect.fromLTWH(left, top, clampedWidth, clampedHeight);
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
      initialBounds: networkMapInitialOriginalAssetBounds(
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
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
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onTap: onTap,
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _NetworkMapStationActionOverlay extends StatelessWidget {
  const _NetworkMapStationActionOverlay({
    required this.station,
    required this.geometry,
    required this.camera,
    required this.onSetOrigin,
    required this.onSetDestination,
    required this.onOpenRouteSearch,
    required this.onClose,
  });

  final NetworkMapStation station;
  final _MapGeometry geometry;
  final MapCameraState camera;
  final VoidCallback onSetOrigin;
  final VoidCallback onSetDestination;
  final VoidCallback onOpenRouteSearch;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final stationPoint = camera.sourceToViewportPoint(
      Offset(geometry.x(station), geometry.y(station)),
    );
    const width = 200.0;
    const height = 44.0;
    final viewportWidth = camera.viewportSize.width;
    final left = (stationPoint.dx - width / 2)
        .clamp(12.0, math.max(12.0, viewportWidth - width - 12))
        .toDouble();
    final top = math.max(12.0, stationPoint.dy - height - 14);
    final arrowLeft = (stationPoint.dx - left - 8).clamp(18.0, width - 34);
    return Positioned(
      key: const Key('networkMapStationSheet'),
      left: left,
      top: top,
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: const Color(0xE8404445),
            elevation: 10,
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: height,
              child: Row(
                children: [
                  _NetworkMapStationActionTab(
                    icon: Icons.north_east,
                    label: '출발',
                    onTap: onSetOrigin,
                  ),
                  _NetworkMapActionDivider(),
                  _NetworkMapStationActionTab(
                    icon: Icons.south_east,
                    label: '도착',
                    onTap: onSetDestination,
                  ),
                  _NetworkMapActionDivider(),
                  _NetworkMapStationActionTab(
                    icon: Icons.route_outlined,
                    label: '길찾기',
                    onTap: onOpenRouteSearch,
                  ),
                  _NetworkMapActionDivider(),
                  _NetworkMapStationActionTab(
                    icon: Icons.close,
                    label: '닫기',
                    onTap: onClose,
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: arrowLeft),
              child: const Icon(
                Icons.arrow_drop_down,
                size: 22,
                color: Color(0xE8404445),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NetworkMapActionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 44,
      child: VerticalDivider(width: 1, color: Color(0x665F6366)),
    );
  }
}

class _NetworkMapStationActionTab extends StatelessWidget {
  const _NetworkMapStationActionTab({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(height: 1),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
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

NetworkMapStation? _stationById(
  List<NetworkMapStation> stations,
  String? stationId,
) {
  if (stationId == null) {
    return null;
  }
  for (final station in stations) {
    if (station.id == stationId) {
      return station;
    }
  }
  return null;
}

NetworkMapStation? _stationByIdentity(
  List<NetworkMapStation> stations,
  NetworkMapStation? selectedStation,
) {
  if (selectedStation == null) {
    return null;
  }
  for (final station in stations) {
    if (station.id == selectedStation.id &&
        station.lineId == selectedStation.lineId) {
      return station;
    }
  }
  return null;
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

List<Map<String, Object?>> _objectList(Object? value) {
  if (value is! List<Object?>) {
    return const [];
  }
  return value
      .whereType<Map<Object?, Object?>>()
      .map((item) => item.cast<String, Object?>())
      .toList(growable: false);
}
