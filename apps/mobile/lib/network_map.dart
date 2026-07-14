import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart' show rootBundle;

import 'accessible_design.dart';
import 'ad_slot.dart';
import 'design_tokens.dart';
import 'facility_report.dart';
import 'features/ads/ad_repository.dart';
import 'features/network_map/domain/map_camera.dart';
import 'features/network_map/domain/route_map_major_stations.dart';
import 'features/network_map/domain/structured_route_map.dart';
import 'features/network_map/presentation/station_fan_menu.dart';
import 'features/network_map/presentation/station_fan_menu_geometry.dart'
    show kFanMenuDesignSize;
import 'features/network_map/presentation/structured_route_map_painter.dart';
import 'features/realtime/realtime_repository.dart';
import 'features/route_draft/application/route_draft_controller.dart';
import 'features/route_draft/domain/route_draft.dart';
import 'internal_route.dart';
import 'mobile_error_reporter.dart';
import 'search_field.dart';
import 'station_search.dart';

const _networkMapTopBarHeight = 60.0;
const _networkMapPillRadius = BorderRadius.all(Radius.circular(8));

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
    this.lineTracks = const [],
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final List<NetworkMapLine> lines;
  final List<NetworkMapStation> stations;
  final List<NetworkMapEdge> edges;
  final List<NetworkMapPositionSource> positionSources;
  final List<NetworkMapStationLineMembership> stationLineMemberships;

  /// 노선별 실제 track polyline (#1638). route_map_line_tracks에서 온다 —
  /// 렌더러 line geometry의 source(역별 down_path 조립을 대체).
  final List<NetworkMapLineTrack> lineTracks;

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
      lineTracks: _objectList(
        json['lineTracks'],
      ).map(NetworkMapLineTrack.fromJson).toList(growable: false),
    );
  }

  /// 구조화 노선도 레이어(#1636 스키마 기준)를 파생한다. native canvas
  /// 렌더러(#1641)가 소비하는 line geometry / transfer group / label·LOD를
  /// route_map_positions 필드에서 계산한다.
  StructuredRouteMap toStructuredRouteMap() {
    // major 거점 allowlist(비환승) 역명 → 현재 지역 station_id 집합(#1764 C).
    // 종점 major는 빌더가 자동 산출하므로 여기서는 거점만 매핑한다.
    final landmarkNames =
        routeMapMajorLandmarkStationNamesByRegion[selectedRegion] ??
        const <String>{};
    final majorStationIds = landmarkNames.isEmpty
        ? const <String>{}
        : <String>{
            for (final station in stations)
              if (landmarkNames.contains(station.nameKo)) station.id,
          };
    return buildStructuredRouteMap(
      stations.map(
        (station) => StructuredRouteMapStationInput(
          stationId: station.id,
          lineId: station.lineId,
          sequence: station.sequence,
          position: Offset(
            station.position.x.toDouble(),
            station.position.y.toDouble(),
          ),
          labelPolygon:
              _parseLabelPolygon(station.position.labelPolygon) ?? const [],
        ),
      ),
      lineTracks: [
        for (final track in lineTracks)
          RouteMapLineTrackInput(lineId: track.lineId, paths: track.paths),
      ],
      majorStationIds: majorStationIds,
    );
  }
}

/// 한 노선의 track 조각들 (#1638). route_map_line_tracks의 path 문자열 목록.
class NetworkMapLineTrack {
  const NetworkMapLineTrack({required this.lineId, required this.paths});

  final String lineId;

  /// track_index 순서의 "M x y L x y ..." path 문자열들.
  final List<String> paths;

  factory NetworkMapLineTrack.fromJson(Map<String, Object?> json) {
    return NetworkMapLineTrack(
      lineId: json['lineId'] as String? ?? '',
      paths:
          (json['paths'] as List<Object?>?)
              ?.map((value) => value as String)
              .toList(growable: false) ??
          const [],
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
    required this.onOpenStationSearch,
    this.onStationSearchClosed,
    this.onPickStationForSlot,
    this.stationSearchRepository,
    this.reportRepository,
    this.favoriteRepository,
    this.adRepository,
    this.searchHistoryRepository,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteMobilityType = 'SENIOR',
    this.locationProvider,
    this.viewportRepository,
    this.realtimeRepository,
    this.onOpenSavedItems,
    this.onOpenNearbyStations,
    this.onOpenSettings,
    this.onOpenDataSources,
    this.onOpenServiceNotices,
    this.notificationAction,
    this.disruptionBanner,
    this.bottomNavigationBar,
    this.focusStationRequestId,
    this.onFocusStationRequestHandled,
    super.key,
  });

  final NetworkMapRepository repository;
  final RouteDraftController routeDraftController;

  /// 역 검색을 열 때 현재 선택 지역 표시명(예: '수도권', '부산')을 함께 전달한다.
  /// #2090에서 검색 화면에 지역 표시가 추가됐는데 호출부가 이를 안 넘겨 기본값
  /// '수도권'이 고정 표시되던 결함을 고치기 위해, 파라미터 없는 VoidCallback에서
  /// `ValueChanged<String>`으로 바꿨다.
  final ValueChanged<String> onOpenStationSearch;

  /// #1933 홈 in-place 역 검색 모드를 빠져나올 때(← 또는 시스템 back) 호출된다.
  /// 셸이 알림/신고 상태를 다시 불러오도록 하기 위한 훅이다. 라우트 기반 검색이
  /// 반환 후 하던 refreshHomeState와 같은 역할을 in-place 종료에도 유지한다.
  final VoidCallback? onStationSearchClosed;

  /// 상단 draft 오버레이의 출발/도착 칸을 탭했을 때, 그 칸을 채우려고 기존 역 검색을
  /// 여는 콜백. 지도 탭과 같은 [routeDraftController]로 수렴한다. null이면 오버레이
  /// 칸은 탭할 수 없다(둘러보기 검색만 메뉴로 제공). 두 번째 인자는 현재 선택 지역
  /// 표시명(#2090 검색 화면 지역 표시 배선).
  final void Function(RouteDraftSlot slot, String regionLabel)?
  onPickStationForSlot;
  final StationSearchRepository? stationSearchRepository;

  /// #1933 홈 노선도 위에서 역 검색을 in-place로 열 때, 결과 탭 → 역 상세로
  /// 이동하려면 필요한 저장소들. 검색 모드는 [stationSearchRepository]가 있을 때만
  /// 진입 가능하다.
  final FacilityReportRepository? reportRepository;
  final FavoriteStationRepository? favoriteRepository;

  final AdRepository? adRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final String internalRouteMobilityType;
  final CurrentLocationProvider? locationProvider;
  final NetworkMapViewportRepository? viewportRepository;
  final RealtimeRepository? realtimeRepository;
  final VoidCallback? onOpenSavedItems;

  /// 현재 선택 지역 표시명을 함께 전달한다(#2090 검색 화면 지역 표시 배선).
  final ValueChanged<String>? onOpenNearbyStations;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenDataSources;

  /// 좌측 메뉴 "운행 공지" 목록 화면 열기.
  final VoidCallback? onOpenServiceNotices;
  final Widget? notificationAction;

  /// 상단 disruption 공지 1줄 배너. 표시할 공지가 없으면 스스로 빈 위젯이 된다.
  final Widget? disruptionBanner;
  final Widget? bottomNavigationBar;

  /// #2109 풀페이지 검색(햄버거 메뉴 경유) 결과 탭으로 반환된 역 id. 설정되면
  /// 노선도가 그 역으로 카메라를 이동하고 팬 메뉴를 띄운다. 임베디드 검색의
  /// _searchFanMenuStationId와 같은 메커니즘을 재사용한다.
  final String? focusStationRequestId;

  /// [focusStationRequestId]를 소비했음을 부모에게 알린다(같은 id로 재요청되지
  /// 않도록 부모가 필드를 비우게 한다).
  final VoidCallback? onFocusStationRequestHandled;

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
  // #2109: 인플레이스 검색 결과 탭으로 연 팬 메뉴의 대상 역 id. 캔버스의
  // selectedStationId(팬 메뉴)와 focusedStationId(카메라 이동)에 함께 실린다.
  String? _searchFanMenuStationId;
  String? _nearbyLookupMessage;
  Timer? _nearbyLookupMessageTimer;
  bool _initialNearbyFocusStarted = false;
  RealtimeSnapshot _nearbyRealtime = const RealtimeSnapshot.loading();
  int _nearbyRealtimeToken = 0;
  late Future<_NetworkMapLoadResult> _future = _loadMap();

  // #1933/#1915 홈 노선도 위 in-place 역 검색 모드. 모드 플래그만 이 화면에
  // 남는다. 검색 컨트롤러·디바운스·최근 검색어·결과 본문 등 키 입력마다 바뀌는
  // 상태는 [_NetworkMapSearchSession]으로 격리해 타이핑이 지도 canvas/chrome을
  // 재빌드하지 않게 한다.
  bool _searchMode = false;

  /// 상단바 편집 필드는 이 화면이 소유하는 컨트롤러/포커스로 그린다(키 입력은
  /// setState를 일으키지 않고 필드가 컨트롤러를 직접 구독해 갱신된다). 검색
  /// 로직은 세션이 소유하므로, 필드 제출은 이 키로 세션에 위임한다.
  final TextEditingController _searchQueryController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final GlobalKey<_NetworkMapSearchSessionState> _searchSessionKey =
      GlobalKey<_NetworkMapSearchSessionState>();

  @override
  void initState() {
    super.initState();
    widget.routeDraftController.addListener(_handleDraftChangedForSearch);
  }

  /// #2109 Fix: 풀페이지 검색(햄버거 메뉴 경유) 결과 탭으로 반환된
  /// [NetworkMapScreen.focusStationRequestId]를 인플레이스 검색과 같은 팬 메뉴
  /// 채널(_searchFanMenuStationId)로 수렴시킨다. 부모([onFocusStationRequestHandled])의
  /// setState를 이 build 사이클 안에서 직접 호출하면 "build 중 setState" 예외가
  /// 나므로(부모가 이 위젯을 빌드하는 도중 didUpdateWidget이 실행됨), 다음
  /// 프레임으로 미룬다.
  @override
  void didUpdateWidget(covariant NetworkMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requestId = widget.focusStationRequestId;
    if (requestId != null && requestId != oldWidget.focusStationRequestId) {
      setState(() {
        _searchFanMenuStationId = requestId;
        // #2109 Fix: 풀페이지 검색으로 팬 메뉴를 여는데 하단 주변 역 패널이 열려
        // 있던 상태(현재 위치 버튼 → 패널 → 햄버거 검색 → 결과 탭 경로)면 팬 메뉴와
        // 패널이 동시에 뜨고 bottomNavigationBar도 계속 억제된다. 팬 메뉴로
        // 수렴하므로 주변 역 패널을 함께 닫아 상호배제한다.
        _resetNearbyPanelState();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFocusStationRequestHandled?.call();
      });
    }
  }

  /// 검색 모드 중 draft가 채워지면(출발/도착 설정 등) OD 상단바가 이겨야 하므로
  /// 검색 모드를 자동 종료한다(co-existence). draft 변경은 키 입력이 아니므로
  /// 이 리스너는 이 화면에 남아도 입력 지연에 영향을 주지 않는다.
  void _handleDraftChangedForSearch() {
    if (_searchMode && !widget.routeDraftController.draft.isEmpty) {
      _exitSearchMode();
    }
  }

  void _enterSearchMode() {
    if (widget.stationSearchRepository == null) {
      return;
    }
    if (!widget.routeDraftController.draft.isEmpty) {
      return;
    }
    setState(() => _searchMode = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchMode) {
        FocusScope.of(context).requestFocus(_searchFocusNode);
      }
    });
  }

  void _exitSearchMode() {
    _searchQueryController.clear();
    if (mounted) {
      setState(() => _searchMode = false);
    } else {
      _searchMode = false;
    }
    widget.onStationSearchClosed?.call();
  }

  /// #2109 일반(비픽) 모드의 인플레이스 검색 결과 탭: 검색을 닫고 해당 역으로
  /// 카메라를 이동한 뒤 부채꼴 팬 메뉴(역 액션 메뉴)를 띄운다.
  void _focusStationFromSearch(StationSearchResult result) {
    // _exitSearchMode 가 이미 setState 로 검색을 닫으므로, 팬 메뉴 상태는 그 뒤
    // 별도 setState 로 세팅해 검색 종료에 덮이지 않도록 한다.
    _exitSearchMode();
    if (!mounted) {
      return;
    }
    setState(() {
      _searchFanMenuStationId = result.id;
    });
  }

  /// #2109 검색 결과 탭으로 연 팬 메뉴가 닫히면(액션 선택·닫기·배경 탭·팬) 이
  /// 화면이 들고 있는 대상 역 id도 비운다. 그러지 않으면 canvas의
  /// selectedStationId prop이 계속 팬 메뉴를 다시 띄운다.
  void _dismissSearchFanMenu() {
    if (_searchFanMenuStationId == null) {
      return;
    }
    setState(() => _searchFanMenuStationId = null);
  }

  /// 상단바 편집 필드의 제출(엔터/검색 액션)을 검색 세션으로 위임한다.
  void _submitSearch(String query) {
    _searchSessionKey.currentState?.submitSearch(query);
  }

  /// 검색 모드일 때만 세션을 만든다. 세션이 검색 상태를 소유하므로 모드 진입
  /// 시 mount·모드 이탈 시 unmount되며, 세션의 initState가 최근 검색어 로드와
  /// 디바운스 구독을 처리한다.
  Widget? _buildSearchBody() {
    if (!_searchMode) {
      return null;
    }
    final searchRepository = widget.stationSearchRepository;
    if (searchRepository == null) {
      return null;
    }
    return _NetworkMapSearchSession(
      key: _searchSessionKey,
      onResultFocus: _focusStationFromSearch,
      searchQueryController: _searchQueryController,
      stationSearchRepository: searchRepository,
      searchHistoryRepository: widget.searchHistoryRepository,
      locationProvider: widget.locationProvider,
    );
  }

  Future<void> _loadNearbyRealtime(StationSearchResult station) async {
    final repository = widget.realtimeRepository;
    final firstLine = station.lines.isEmpty ? null : station.lines.first;
    final token = ++_nearbyRealtimeToken;
    if (repository == null || firstLine == null) {
      setState(() {
        _nearbyRealtime = const RealtimeSnapshot(
          status: RealtimeSnapshotStatus.unsupported,
          fallbackCode: 'LINE_MAPPING_MISSING',
          message: '이 노선은 아직 실시간 열차 안내가 어려워요.',
        );
      });
      return;
    }
    setState(() => _nearbyRealtime = const RealtimeSnapshot.loading());
    RealtimeSnapshot snapshot;
    try {
      snapshot = await repository.arrivals(
        RealtimeStationQuery(
          stationId: station.id,
          lineId: firstLine.id,
          providerLineId: firstLine.stationCode.isEmpty
              ? firstLine.id
              : firstLine.stationCode,
          stationQueryName: station.nameKo,
        ),
      );
    } on RealtimeException {
      snapshot = const RealtimeSnapshot.unavailable();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '노선도 주변역 실시간 조회 중 예외가 발생했습니다.',
      );
      snapshot = const RealtimeSnapshot.unavailable();
    }
    if (!mounted || token != _nearbyRealtimeToken) {
      return;
    }
    setState(() => _nearbyRealtime = snapshot);
  }

  @override
  void dispose() {
    _nearbyLookupMessageTimer?.cancel();
    widget.routeDraftController.removeListener(_handleDraftChangedForSearch);
    _searchQueryController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<_NetworkMapLoadResult> _loadMap() async {
    final data = await widget.repository.getNetworkMap(region: _selectedRegion);
    // #2082/#2083 후속: 저장된(persisted) 지역이 있는 사용자는 세션 중
    // 지역 선택기를 조작하지 않는 한 _selectedRegion이 계속 null이라, 로드된
    // 실제 지역(data.selectedRegion)을 여기서 동기화해둔다. 사용자가 이미
    // _reload(region: ...)로 _selectedRegion을 명시 설정한 경우는 그 값이
    // 그대로 리포지토리 요청에 반영되어 data.selectedRegion과 같아지므로
    // 값이 보존된다(덮어써도 동일).
    _selectedRegion = data.selectedRegion;
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
      _nearbyRealtime = const RealtimeSnapshot.loading();
      _nearbyRealtimeToken++;
      _initialNearbyFocusStarted = false;
      _future = _loadMap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_searchMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _searchMode) {
          _exitSearchMode();
        }
      },
      child: Scaffold(
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
                disruptionBanner: widget.disruptionBanner,
                onMenuTap: _openMapMenu,
                onSearchTap: _enterSearchMode,
                searchMode: _searchMode,
                searchBody: _buildSearchBody(),
                onSearchBack: _exitSearchMode,
                searchQueryController: _searchQueryController,
                searchFocusNode: _searchFocusNode,
                onSearchSubmitted: _submitSearch,
                onSearchClear: _searchQueryController.clear,
                onRegionSelected: (region) => _reload(region: region),
                onExpressViewChanged: (value) {
                  setState(() => _expressView = value);
                },
                nearbyPanelVisible: _nearbyPanelVisible,
                nearbyPanelData: _nearbyPanelData,
                realtime: _nearbyRealtime,
                nearbyLookupMessage: _nearbyLookupMessage,
                adjacentStations: const _NetworkMapAdjacentStations(),
                onCurrentLocationTap: _showNearbyPanel,
                onOpenNearbyStations: _openNearbyStationsWithRegion,
                onCloseNearbyPanel: _hideNearbyPanel,
                routeDraftController: widget.routeDraftController,
                onClearOrigin: _clearOriginStation,
                onClearDestination: _clearDestinationStation,
                onClearWaypoint: _clearWaypointStation,
                onSwapDraft: _swapDraftStations,
                onReorderDraft: _reorderDraftStations,
                onPickOrigin: widget.onPickStationForSlot == null
                    ? null
                    : _pickOriginStation,
                onPickDestination: widget.onPickStationForSlot == null
                    ? null
                    : _pickDestinationStation,
                onPickWaypoint: widget.onPickStationForSlot == null
                    ? null
                    : _pickWaypointStation,
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
                disruptionBanner: widget.disruptionBanner,
                onMenuTap: _openMapMenu,
                onSearchTap: _enterSearchMode,
                searchMode: _searchMode,
                searchBody: _buildSearchBody(),
                onSearchBack: _exitSearchMode,
                searchQueryController: _searchQueryController,
                searchFocusNode: _searchFocusNode,
                onSearchSubmitted: _submitSearch,
                onSearchClear: _searchQueryController.clear,
                onRegionSelected: (region) => _reload(region: region),
                onExpressViewChanged: (value) {
                  setState(() => _expressView = value);
                },
                nearbyPanelVisible: _nearbyPanelVisible,
                nearbyPanelData: _nearbyPanelData,
                realtime: _nearbyRealtime,
                nearbyLookupMessage: _nearbyLookupMessage,
                adjacentStations: const _NetworkMapAdjacentStations(),
                onCurrentLocationTap: _showNearbyPanel,
                onOpenNearbyStations: _openNearbyStationsWithRegion,
                onCloseNearbyPanel: _hideNearbyPanel,
                routeDraftController: widget.routeDraftController,
                onClearOrigin: _clearOriginStation,
                onClearDestination: _clearDestinationStation,
                onClearWaypoint: _clearWaypointStation,
                onSwapDraft: _swapDraftStations,
                onReorderDraft: _reorderDraftStations,
                onPickOrigin: widget.onPickStationForSlot == null
                    ? null
                    : _pickOriginStation,
                onPickDestination: widget.onPickStationForSlot == null
                    ? null
                    : _pickDestinationStation,
                onPickWaypoint: widget.onPickStationForSlot == null
                    ? null
                    : _pickWaypointStation,
                child: _NetworkMapLoadFailure(onRetry: () => _reload()),
              );
            }
            final loadResult = snapshot.data!;
            final data = loadResult.data;
            final hasExpressLines = _expressLineIds(data).isNotEmpty;
            // #1641: 모든 지역이 구조화 canvas로 렌더되므로 express 필터·서비스 패턴
            // 토글이 전 지역에 균일 적용된다(과거 SVG 지역 예외 제거).
            final visibleData = hasExpressLines && _expressView
                ? _expressOnlyMapData(data)
                : data;
            _startInitialNearbyFocus();
            return _NetworkMapChrome(
              regions: data.regions,
              selectedRegion: data.selectedRegion,
              expressView: _expressView,
              showServicePatternToggle: true,
              notificationAction: widget.notificationAction,
              disruptionBanner: widget.disruptionBanner,
              onMenuTap: _openMapMenu,
              onSearchTap: _enterSearchMode,
              searchMode: _searchMode,
              searchBody: _buildSearchBody(),
              onSearchBack: _exitSearchMode,
              searchQueryController: _searchQueryController,
              searchFocusNode: _searchFocusNode,
              onSearchSubmitted: _submitSearch,
              onSearchClear: _searchQueryController.clear,
              onRegionSelected: (region) => _reload(region: region),
              onExpressViewChanged: (value) {
                setState(() => _expressView = value);
              },
              nearbyPanelVisible: _nearbyPanelVisible,
              nearbyPanelData: _nearbyPanelData,
              realtime: _nearbyRealtime,
              nearbyLookupMessage: _nearbyLookupMessage,
              adjacentStations: _adjacentStationsFor(data),
              onCurrentLocationTap: _showNearbyPanel,
              onOpenNearbyStations: _openNearbyStationsWithRegion,
              onCloseNearbyPanel: _hideNearbyPanel,
              routeDraftController: widget.routeDraftController,
              onClearOrigin: _clearOriginStation,
              onClearDestination: _clearDestinationStation,
              onClearWaypoint: _clearWaypointStation,
              onSwapDraft: _swapDraftStations,
              onReorderDraft: _reorderDraftStations,
              onPickOrigin: widget.onPickStationForSlot == null
                  ? null
                  : _pickOriginStation,
              onPickDestination: widget.onPickStationForSlot == null
                  ? null
                  : _pickDestinationStation,
              onPickWaypoint: widget.onPickStationForSlot == null
                  ? null
                  : _pickWaypointStation,
              // #1933: _setOriginStation은 routeDraftController만 갱신하고 이
              // State에서 setState를 호출하지 않으므로, canvas를 좁게
              // ListenableBuilder로 감싸 draft 변경 시 하위 트리가 다시
              // 계산되게 한다(그래야 슬롯 배정 상태가 즉시 반영됨).
              child: ListenableBuilder(
                listenable: widget.routeDraftController,
                builder: (context, _) {
                  return _NetworkMapCanvas(
                    data: visibleData,
                    initialViewport: loadResult.initialViewport,
                    focusedStationId:
                        _searchFanMenuStationId ?? _nearbySelectedStationId,
                    selectedStationId:
                        _searchFanMenuStationId ??
                        (_nearbyPanelVisible ? _nearbySelectedStationId : null),
                    onSelectionDismissed: _dismissSearchFanMenu,
                    originStationId:
                        widget.routeDraftController.draft.origin?.id,
                    waypointStationId:
                        widget.routeDraftController.draft.waypoint?.id,
                    destinationStationId:
                        widget.routeDraftController.draft.destination?.id,
                    onSetOrigin: _setOriginStation,
                    onSetWaypoint: _setWaypointStation,
                    onSetDestination: _setDestinationStation,
                    onClearOrigin: _clearOriginStation,
                    onClearWaypoint: _clearWaypointStation,
                    onClearDestination: _clearDestinationStation,
                    onViewportChanged: (viewport) {
                      _saveRecentViewport(data.selectedRegion, viewport);
                    },
                  );
                },
              ),
            );
          },
        ),
        bottomNavigationBar: _searchMode || _nearbyPanelVisible
            ? null
            : const _NetworkMapBottomAdBanner(),
      ),
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
      unawaited(_loadNearbyRealtime(results.first));
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
    _nearbyLookupMessageTimer = Timer(const Duration(seconds: 4), () {
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

  void _resetNearbyPanelState() {
    _nearbyPanelVisible = false;
    _nearbySelectedStationId = null;
    _nearbyPanelData = const _NetworkMapNearbyPanelData.idle();
    _nearbyRealtime = const RealtimeSnapshot.loading();
    _nearbyRealtimeToken++;
  }

  void _hideNearbyPanel() => setState(_resetNearbyPanelState);

  /// 현재 선택 지역의 표시명(예: '수도권', '부산'). 역 검색 화면을 열 때
  /// [StationSearchScreen.regionLabel]로 그대로 넘긴다(#2090 배선).
  String get _currentRegionDisplayName =>
      _displayRegionName(_selectedRegion ?? '수도권');

  /// 파라미터 없는 [VoidCallback]만 받는 하위 위젯(_NetworkMapChrome,
  /// _NetworkMapMenuPanel)에 현재 지역을 실어 전달하기 위한 래퍼.
  VoidCallback? get _openNearbyStationsWithRegion {
    final callback = widget.onOpenNearbyStations;
    if (callback == null) {
      return null;
    }
    return () => callback(_currentRegionDisplayName);
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
          onOpenStationSearch: () =>
              widget.onOpenStationSearch(_currentRegionDisplayName),
          onOpenSavedItems: widget.onOpenSavedItems,
          onOpenNearbyStations: _openNearbyStationsWithRegion,
          onOpenServiceNotices: widget.onOpenServiceNotices,
          onOpenSettings: widget.onOpenSettings,
          onOpenDataSources: widget.onOpenDataSources,
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

  void _setWaypointStation(NetworkMapStation station) {
    widget.routeDraftController.setWaypoint(
      RouteDraftStation(id: station.id, nameKo: station.nameKo),
    );
  }

  void _clearOriginStation() {
    widget.routeDraftController.clearOrigin();
  }

  void _clearDestinationStation() {
    widget.routeDraftController.clearDestination();
  }

  void _clearWaypointStation() {
    widget.routeDraftController.clearWaypoint();
  }

  void _swapDraftStations() {
    widget.routeDraftController.swapOriginDestination();
  }

  /// #1985: draft 행 드래그 재배열. 대상 슬롯이 이미 차 있으면 두 값을 맞바꾸고,
  /// 비어 있으면 값을 옮긴다. 컨트롤러가 어느 경우든 원자적으로 처리한다.
  void _reorderDraftStations(RouteDraftSlot from, RouteDraftSlot to) {
    final draft = widget.routeDraftController.draft;
    final toFilled = switch (to) {
      RouteDraftSlot.origin => draft.origin != null,
      RouteDraftSlot.destination => draft.destination != null,
      RouteDraftSlot.waypoint => draft.waypoint != null,
    };
    if (toFilled) {
      widget.routeDraftController.swapSlots(from, to);
    } else {
      widget.routeDraftController.moveSlot(from, to);
    }
  }

  /// G4: 상단 오버레이 출발 칸 탭 → 기존 역 검색을 "출발역 채우기" 모드로 연다.
  /// 지도 탭 경로와 같은 [routeDraftController]로 수렴한다.
  void _pickOriginStation() {
    widget.onPickStationForSlot?.call(
      RouteDraftSlot.origin,
      _currentRegionDisplayName,
    );
  }

  /// G4: 상단 오버레이 도착 칸 탭 → 기존 역 검색을 "도착역 채우기" 모드로 연다.
  void _pickDestinationStation() {
    widget.onPickStationForSlot?.call(
      RouteDraftSlot.destination,
      _currentRegionDisplayName,
    );
  }

  /// #1948: 상단 오버레이 경유 행·추가 진입점 탭 → 역 검색을 "경유역 채우기" 모드로 연다.
  void _pickWaypointStation() {
    widget.onPickStationForSlot?.call(
      RouteDraftSlot.waypoint,
      _currentRegionDisplayName,
    );
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

/// 테스트 전용: [_NetworkMapChrome]가 build될 때마다 증가한다. 검색 중 키
/// 입력이 지도 chrome(상단바+지도 canvas를 감싸는 서브트리) 전체를 재빌드하지
/// 않는지(입력 지연 회귀 방지 #1915) 검증하는 회귀 테스트에서만 읽는다.
@visibleForTesting
int debugNetworkMapChromeBuildCount = 0;

class _NetworkMapChrome extends StatelessWidget {
  const _NetworkMapChrome({
    required this.regions,
    required this.selectedRegion,
    required this.expressView,
    required this.showServicePatternToggle,
    required this.notificationAction,
    required this.disruptionBanner,
    required this.onMenuTap,
    required this.onSearchTap,
    required this.onRegionSelected,
    required this.onExpressViewChanged,
    required this.nearbyPanelVisible,
    required this.nearbyPanelData,
    required this.realtime,
    required this.nearbyLookupMessage,
    required this.adjacentStations,
    required this.onCurrentLocationTap,
    required this.onOpenNearbyStations,
    required this.onCloseNearbyPanel,
    required this.routeDraftController,
    required this.onClearOrigin,
    required this.onClearDestination,
    required this.onClearWaypoint,
    required this.onSwapDraft,
    required this.onReorderDraft,
    this.onPickOrigin,
    this.onPickDestination,
    this.onPickWaypoint,
    this.searchMode = false,
    this.searchBody,
    this.onSearchBack,
    this.searchQueryController,
    this.searchFocusNode,
    this.onSearchSubmitted,
    this.onSearchClear,
    required this.child,
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final bool expressView;
  final bool showServicePatternToggle;
  final Widget? notificationAction;
  final Widget? disruptionBanner;
  final VoidCallback onMenuTap;
  final VoidCallback onSearchTap;
  final ValueChanged<String> onRegionSelected;
  final ValueChanged<bool> onExpressViewChanged;
  final bool nearbyPanelVisible;
  final _NetworkMapNearbyPanelData nearbyPanelData;
  final RealtimeSnapshot realtime;
  final String? nearbyLookupMessage;
  final _NetworkMapAdjacentStations adjacentStations;
  final VoidCallback onCurrentLocationTap;
  final VoidCallback? onOpenNearbyStations;
  final VoidCallback onCloseNearbyPanel;
  final RouteDraftController routeDraftController;
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDestination;
  final VoidCallback onClearWaypoint;
  final VoidCallback onSwapDraft;

  /// #1985: draft 행 드래그 재배열 콜백. (from, to) 슬롯을 받아 swap/move를 분기한다.
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorderDraft;

  /// 상단바 출발/도착/경유 칸 탭 → 역 검색 열기. null이면 칸을 탭할 수 없다.
  final VoidCallback? onPickOrigin;
  final VoidCallback? onPickDestination;
  final VoidCallback? onPickWaypoint;

  /// #1933 홈 노선도 in-place 역 검색 모드. true면 body를 [searchBody]로 바꾸고
  /// 상단바 좌측 ≡를 ←로, 검색 필드를 실제 TextField로 전환한다. 지역 선택기는
  /// 두 모드에서 모두 유지된다.
  final bool searchMode;
  final Widget? searchBody;
  final VoidCallback? onSearchBack;
  final TextEditingController? searchQueryController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchClear;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    debugNetworkMapChromeBuildCount++;
    final topPadding = MediaQuery.paddingOf(context).top;
    final inSearchMode = searchMode && searchBody != null;
    return Stack(
      children: [
        Positioned.fill(
          top: topPadding + _networkMapTopBarHeight,
          child: ClipRect(child: inSearchMode ? searchBody! : child),
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
            searchMode: inSearchMode,
            onSearchBack: onSearchBack,
            searchQueryController: searchQueryController,
            searchFocusNode: searchFocusNode,
            onSearchSubmitted: onSearchSubmitted,
            onSearchClear: onSearchClear,
            onRegionSelected: onRegionSelected,
            // #1933 요구 2: 출발/도착이 하나라도 차면 상단바 자체가 출발/도착
            // 2줄 입력으로 "변신"한다(아래 별도 카드 없음). 지도 탭·검색 어느
            // 경로든 같은 [routeDraftController]로 수렴한다.
            routeDraftController: routeDraftController,
            onClearOrigin: onClearOrigin,
            onClearDestination: onClearDestination,
            onClearWaypoint: onClearWaypoint,
            onSwapDraft: onSwapDraft,
            onReorderDraft: onReorderDraft,
            onPickOrigin: onPickOrigin,
            onPickDestination: onPickDestination,
            onPickWaypoint: onPickWaypoint,
          ),
        ),
        if (disruptionBanner != null && !inSearchMode)
          Positioned(
            left: 0,
            right: 0,
            top: topPadding + _networkMapTopBarHeight,
            child: disruptionBanner!,
          ),
        if (showServicePatternToggle && !inSearchMode)
          Positioned(
            left: 16,
            bottom: 26,
            child: _NetworkMapServicePatternToggle(
              expressView: expressView,
              onChanged: onExpressViewChanged,
            ),
          ),
        if (nearbyPanelVisible && !inSearchMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _NetworkMapNearbyStationPanel(
              data: nearbyPanelData,
              realtime: realtime,
              adjacentStations: adjacentStations,
              onClose: onCloseNearbyPanel,
              onRetry: onCurrentLocationTap,
            ),
          ),
        if (nearbyLookupMessage != null && !inSearchMode)
          Positioned(
            left: 24,
            right: 24,
            bottom: nearbyPanelVisible ? 318 : 132,
            child: _NetworkMapLookupToast(message: nearbyLookupMessage!),
          ),
        if (onOpenNearbyStations != null && !inSearchMode)
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
        elevation: 0,
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
    this.searchMode = false,
    this.onSearchBack,
    this.searchQueryController,
    this.searchFocusNode,
    this.onSearchSubmitted,
    this.onSearchClear,
    required this.onRegionSelected,
    required this.routeDraftController,
    required this.onClearOrigin,
    required this.onClearDestination,
    required this.onClearWaypoint,
    required this.onSwapDraft,
    required this.onReorderDraft,
    this.onPickOrigin,
    this.onPickDestination,
    this.onPickWaypoint,
  });

  final List<NetworkMapRegion> regions;
  final String selectedRegion;
  final Widget? notificationAction;
  final VoidCallback onMenuTap;
  final VoidCallback onSearchTap;
  final bool searchMode;
  final VoidCallback? onSearchBack;
  final TextEditingController? searchQueryController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onSearchClear;
  final ValueChanged<String> onRegionSelected;
  final RouteDraftController routeDraftController;
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDestination;
  final VoidCallback onClearWaypoint;
  final VoidCallback onSwapDraft;
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorderDraft;
  final VoidCallback? onPickOrigin;
  final VoidCallback? onPickDestination;
  final VoidCallback? onPickWaypoint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: EasySubwayAccessibleColors.surface,
      elevation: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: EasySubwayAccessibleColors.line),
          ),
        ),
        child: SafeArea(
          bottom: false,
          // #1933 요구 2: draft가 비면 검색바, 하나라도 차면 출발/도착 2줄 입력으로
          // 상단바 자체가 변신한다. 별도 카드를 아래에 띄우지 않는다.
          child: ListenableBuilder(
            listenable: routeDraftController,
            builder: (context, _) {
              final draft = routeDraftController.draft;
              if (draft.isEmpty) {
                return _buildSearchRow(context);
              }
              return _NetworkMapTopBarRouteDraft(
                key: const Key('networkMapRouteDraftOverlay'),
                draft: draft,
                onClearOrigin: onClearOrigin,
                onClearDestination: onClearDestination,
                onClearWaypoint: onClearWaypoint,
                onSwapDraft: onSwapDraft,
                onReorderDraft: onReorderDraft,
                onPickOrigin: onPickOrigin,
                onPickDestination: onPickDestination,
                onPickWaypoint: onPickWaypoint,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSearchRow(BuildContext context) {
    final currentRegion = _displayRegionName(selectedRegion);
    final availableRegions = regions.isEmpty
        ? const [NetworkMapRegion(name: '수도권')]
        : regions;
    return SizedBox(
      height: _networkMapTopBarHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Row(
          children: [
            if (searchMode)
              IconButton(
                key: const Key('networkMapSearchBackButton'),
                tooltip: '뒤로',
                onPressed: onSearchBack,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(EasySubwayTouchTarget.general),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(
                  Icons.arrow_back,
                  size: 26,
                  color: Color(0xFF4B4B4B),
                ),
              )
            else
              IconButton(
                key: const Key('networkMapMenuButton'),
                tooltip: '메뉴',
                onPressed: onMenuTap,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(EasySubwayTouchTarget.general),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(
                  Icons.menu,
                  size: 26,
                  color: Color(0xFF4B4B4B),
                ),
              ),
            const SizedBox(width: 4),
            Expanded(
              child: searchMode
                  ? EasySubwaySearchField(
                      controller: searchQueryController,
                      focusNode: searchFocusNode,
                      hintText: '역 이름을 입력해 주세요',
                      autofocus: true,
                      onSubmitted: onSearchSubmitted,
                      onClear: onSearchClear,
                    )
                  : _NetworkMapSearchField(onSearchTap: onSearchTap),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (regionContext) => Semantics(
                key: const Key('mapRegionTabs'),
                container: true,
                button: true,
                label: '지역: $currentRegion, 지역 변경',
                // 시맨틱 활성화 액션을 제공해 스크린리더로도 지역 메뉴를 연다
                // (형제 검색 필드와 동일한 패턴).
                onTap: () => _showRegionMenu(regionContext, availableRegions),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 148),
                  child: ExcludeSemantics(
                    // 트리거의 ▾ 캐럿과 반응 위치를 맞춘다: 트리거 바로 아래
                    // 앵커된 드롭다운 메뉴로 지역을 표시한다(하단 시트 대신).
                    child: InkWell(
                      key: const Key('networkMapRegionDropdown'),
                      onTap: () =>
                          _showRegionMenu(regionContext, availableRegions),
                      splashFactory: NoSplash.splashFactory,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      child: SizedBox(
                        height: EasySubwayTouchTarget.general,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                currentRegion,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF606060),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF606060),
                              size: 22,
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
    );
  }

  Future<void> _showRegionMenu(
    BuildContext triggerContext,
    List<NetworkMapRegion> availableRegions,
  ) async {
    final RenderBox? triggerBox =
        triggerContext.findRenderObject() as RenderBox?;
    final RenderBox? overlayBox =
        Overlay.of(triggerContext).context.findRenderObject() as RenderBox?;
    if (triggerBox == null || overlayBox == null) {
      return;
    }
    final topRight = triggerBox.localToGlobal(
      triggerBox.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    );
    final topY = topRight.dy;
    await showGeneralDialog<String>(
      context: triggerContext,
      barrierDismissible: true,
      barrierLabel: '지역 메뉴 닫기',
      // 참고 07에서 차용하는 것은 모달 구조가 아니라 주변을 어둡게 해
      // 노선도 색 소음을 죽이는 딤 스크림뿐이다. 앱 다이얼로그 관례값
      // (Color(0x99000000))과 동일하게 맞춰 메뉴 뒤를 어둡게 한다. 메뉴는
      // 현행대로 트리거 바로 아래·화면 우측 밀착 위치를 유지한다.
      barrierColor: const Color(0x99000000),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              top: topY,
              right: 0,
              child: _NetworkMapRegionMenuOverlay(
                availableRegions: availableRegions,
                selectedRegion: selectedRegion,
                onRegionSelected: onRegionSelected,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NetworkMapRegionMenuOverlay extends StatelessWidget {
  const _NetworkMapRegionMenuOverlay({
    required this.availableRegions,
    required this.selectedRegion,
    required this.onRegionSelected,
  });

  final List<NetworkMapRegion> availableRegions;
  final String selectedRegion;
  final ValueChanged<String> onRegionSelected;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < availableRegions.length; i++) {
      final region = availableRegions[i];
      final isSelected = region.name == selectedRegion;
      rows.add(
        InkWell(
          key: ValueKey('networkMapRegionMenuRow_${region.name}'),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () {
            onRegionSelected(region.name);
            Navigator.of(context).pop();
          },
          child: SizedBox(
            height: 48,
            child: Semantics(
              button: true,
              selected: isSelected,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // 라벨은 좌측 기준(좌패딩 16), ✓는 행 오른쪽 끝(우패딩 16)에
                    // 트레일링으로 둔다(참고 07과 동일 배치). 비선택 행은
                    // 트레일링 자리를 비운다 — 라벨이 좌측 기준이라 정렬용
                    // 고정 폭은 불필요하다.
                    Expanded(
                      child: Text(
                        region.displayName,
                        style: TextStyle(
                          color: EasySubwayAccessibleColors.listRowText,
                          fontSize: 16,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.check,
                        color: EasySubwayAccessibleColors.mutedText,
                        size: 20,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (i != availableRegions.length - 1) {
        rows.add(const _NetworkMapRegionMenuDivider());
      }
    }
    return ConstrainedBox(
      // 콘텐츠 자연폭을 따르되(IntrinsicWidth), 극단 협폭만 방지할 정도의
      // 하한만 둔다. 폭을 강제로 넓히지 않는다.
      constraints: const BoxConstraints(minWidth: 120),
      child: IntrinsicWidth(
        child: Material(
          elevation: 0,
          color: EasySubwayAccessibleColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: EasySubwayAccessibleColors.line),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(EasySubwayRadius.control),
              bottomLeft: Radius.circular(EasySubwayRadius.control),
              topRight: Radius.zero,
              bottomRight: Radius.zero,
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }
}

class _NetworkMapRegionMenuDivider extends StatelessWidget {
  const _NetworkMapRegionMenuDivider();

  @override
  Widget build(BuildContext context) {
    // full-width 절단형은 행을 과하게 분리해 보이게 하므로, 텍스트 시작선
    // (좌 16)부터 우 16 전까지의 인셋 구분선으로 둔다. 색·두께는 유지.
    return const Padding(
      key: Key('networkMapRegionMenuDivider'),
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: EasySubwayAccessibleColors.line),
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
        // 입력 필드처럼 보이되 탭 시 어떤 ink 하이라이트/사각형도 뜨지 않게
        // GestureDetector로 처리한다(InkWell의 transparent color로는 상위
        // Material에 사각형이 남을 수 있음). 탭하면 조용히 검색 화면으로 전환. #1933
        child: GestureDetector(
          key: const Key('stationSearchButton'),
          behavior: HitTestBehavior.opaque,
          onTap: onSearchTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 72;
              return SizedBox(
                height: EasySubwayTouchTarget.general,
                child: Center(
                  child: Container(
                    key: const Key('heroStationSearchButton'),
                    height: easySubwaySearchFieldVisualHeight,
                    decoration: BoxDecoration(
                      color: EasySubwayAccessibleColors.surface,
                      border: Border.all(
                        color: EasySubwayAccessibleColors.line,
                        width: easySubwaySearchFieldBorderWidth,
                      ),
                      borderRadius: easySubwaySearchFieldRadius,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: compact
                          ? 0
                          : easySubwaySearchFieldHorizontalPadding,
                    ),
                    child: compact
                        ? const SizedBox.shrink()
                        : const Row(
                            children: [
                              Icon(
                                Icons.search,
                                size: easySubwaySearchFieldIconSize,
                                color: EasySubwayAccessibleColors.iconMuted,
                              ),
                              SizedBox(width: easySubwaySearchFieldIconGap),
                              Expanded(
                                child: Text(
                                  '지하철역 검색',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: easySubwaySearchFieldHintStyle,
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

/// #1915 홈 노선도 in-place 역 검색의 "세션" — 검색 컨트롤러·디바운스·최근
/// 검색어·결과 본문 등 키 입력마다 바뀌는 상태를 이 서브트리로 격리한다.
/// 검색 모드로 진입/이탈하는 모드 플래그만 상위 [_NetworkMapScreenState]에
/// 남고, 타이핑으로 인한 재빌드는 이 세션(검색 필드 지우기 버튼·결과 본문)에
/// 국한된다. 그래야 지도 canvas·chrome 서브트리가 키 입력마다 재빌드되지
/// 않아 입력 지연이 사라진다.
///
/// 상단바의 편집 필드는 [_NetworkMapChrome]의 별도 Stack 자식이라 이 세션이
/// 직접 렌더하지 않는다. 대신 필드의 컨트롤러([searchQueryController])를 상위와
/// 공유하고, 세션은 그 컨트롤러를 구독해 디바운스 검색을 돌린다. 필드의 지우기
/// 버튼과 결과 본문은 각각 컨트롤러를 직접 구독(ListenableBuilder/
/// AnimatedBuilder)하므로 상위 setState 없이 자체 갱신된다. 제출(엔터/검색
/// 액션)은 상위가 [GlobalKey]로 [submitSearch]를 호출해 세션 로직으로 넘긴다.
class _NetworkMapSearchSession extends StatefulWidget {
  const _NetworkMapSearchSession({
    super.key,
    required this.onResultFocus,
    required this.searchQueryController,
    required this.stationSearchRepository,
    required this.searchHistoryRepository,
    required this.locationProvider,
  });

  final ValueChanged<StationSearchResult> onResultFocus;
  final TextEditingController searchQueryController;
  final StationSearchRepository stationSearchRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final CurrentLocationProvider? locationProvider;

  @override
  State<_NetworkMapSearchSession> createState() =>
      _NetworkMapSearchSessionState();
}

class _NetworkMapSearchSessionState extends State<_NetworkMapSearchSession> {
  late final StationSearchController _searchController;
  Timer? _searchDebounce;
  List<String> _searchRecentQueries = const [];
  bool _searchOpeningLocationSettings = false;

  TextEditingController get _queryController => widget.searchQueryController;

  bool get _hasSearchQuery => _queryController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _searchController = StationSearchController(
      repository: widget.stationSearchRepository,
      searchHistoryRepository: widget.searchHistoryRepository,
    );
    _queryController.addListener(_handleSearchQueryChanged);
    unawaited(_loadSearchRecentQueries());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _queryController.removeListener(_handleSearchQueryChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchQueryChanged() {
    if (!mounted) {
      return;
    }
    _searchDebounce?.cancel();
    if (!_hasSearchQuery) {
      if (_searchController.state.status != StationSearchStatus.idle) {
        unawaited(_searchController.search(''));
      }
      return;
    }
    final query = _queryController.text;
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_runInPlaceSearch(query, recordHistory: false)),
    );
  }

  Future<void> _runInPlaceSearch(
    String query, {
    bool recordHistory = true,
  }) async {
    await _searchController.search(query, recordHistory: recordHistory);
    if (recordHistory) {
      await _loadSearchRecentQueries();
    }
  }

  /// 상위 화면이 상단바 편집 필드의 제출(엔터/검색 액션)에서 [GlobalKey]로
  /// 호출한다. 세션이 검색 로직을 소유하므로 제출도 세션에서 처리한다.
  void submitSearch(String query) {
    _searchDebounce?.cancel();
    if (_searchController.state.status == StationSearchStatus.loading) {
      return;
    }
    unawaited(_runInPlaceSearch(query));
  }

  Future<void> _loadSearchRecentQueries() async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      final queries = await repository.listRecentQueries();
      if (!mounted) {
        return;
      }
      setState(() => _searchRecentQueries = queries);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색어 조회 중 예외가 발생했습니다.');
    }
  }

  void _searchRecentQuerySelected(String query) {
    _queryController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    submitSearch(query);
  }

  Future<void> _removeSearchRecentQuery(String query) async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.removeSearch(query);
      await _loadSearchRecentQueries();
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '최근 검색어 삭제 중 예외가 발생했습니다.');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('최근 검색을 지우지 못했어요.')));
      }
    }
  }

  Future<void> _clearSearchRecentQueries() async {
    final repository = widget.searchHistoryRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.clearSearches();
      await _loadSearchRecentQueries();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '최근 검색어 전체 삭제 중 예외가 발생했습니다.',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('최근 검색을 지우지 못했어요.')));
      }
    }
  }

  Future<void> _openSearchLocationSettings() async {
    final locationProvider = widget.locationProvider;
    if (_searchOpeningLocationSettings || locationProvider == null) {
      return;
    }
    setState(() => _searchOpeningLocationSettings = true);
    try {
      await locationProvider.openLocationSettings();
    } finally {
      if (mounted) {
        setState(() => _searchOpeningLocationSettings = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EasySubwayAccessibleColors.scaffoldSurface,
      child: SafeArea(
        top: false,
        child: Semantics(
          container: true,
          child: AnimatedBuilder(
            animation: Listenable.merge([_searchController, _queryController]),
            builder: (context, _) {
              final state = _searchController.state;
              final showRecent =
                  !_hasSearchQuery && _searchRecentQueries.isNotEmpty;
              final isSearching = state.status == StationSearchStatus.loading;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (showRecent)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: StationRecentSearchSection(
                        queries: _searchRecentQueries,
                        enabled: !isSearching,
                        onQuerySelected: _searchRecentQuerySelected,
                        onQueryRemoved: (query) =>
                            unawaited(_removeSearchRecentQuery(query)),
                        onClearAll: () =>
                            unawaited(_clearSearchRecentQueries()),
                      ),
                    ),
                  StationSearchBody(
                    state: state,
                    onResultTap: widget.onResultFocus,
                    isOpeningLocationSettings: _searchOpeningLocationSettings,
                    onOpenLocationSettings: () =>
                        unawaited(_openSearchLocationSettings()),
                  ),
                ],
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
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: _networkMapPillRadius,
        side: BorderSide(color: EasySubwayAccessibleColors.line),
      ),
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
          elevation: 0,
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
    required this.realtime,
    required this.adjacentStations,
    required this.onClose,
    required this.onRetry,
  });

  final _NetworkMapNearbyPanelData data;
  final RealtimeSnapshot realtime;
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
      elevation: 0,
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
                    if (realtime.status == RealtimeSnapshotStatus.fresh)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          height: 24,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: EasySubwayAccessibleColors.mintBorder,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '실시간',
                            style: TextStyle(
                              color: EasySubwayAccessibleColors.mint,
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
                realtime: realtime,
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
    required this.realtime,
    required this.adjacentStations,
  });

  final _NetworkMapNearbyPanelData data;
  final RealtimeSnapshot realtime;
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
        realtime: realtime,
        adjacentStations: adjacentStations,
      ),
    };
  }
}

class _NetworkMapNearbySuccessList extends StatelessWidget {
  const _NetworkMapNearbySuccessList({
    required this.results,
    required this.realtime,
    required this.adjacentStations,
  });

  final List<StationSearchResult> results;
  final RealtimeSnapshot realtime;
  final _NetworkMapAdjacentStations adjacentStations;

  @override
  Widget build(BuildContext context) {
    final primary = results.first;
    final leftName = adjacentStations.leftName;
    final rightName = adjacentStations.rightName;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(13, 18, 13, 0),
          child: Container(
            height: 26,
            decoration: BoxDecoration(
              color: EasySubwayAccessibleColors.mapSelectionAccent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    leftName == null ? '' : '< $leftName',
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
                      color: EasySubwayAccessibleColors.mapSelectionAccent,
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
                    rightName == null ? '' : '$rightName >',
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
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: _SubwayArrivalPanel(snapshot: realtime),
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

String _formatArrivalEta(RealtimeArrival arrival) {
  final eta = arrival.etaSeconds;
  if (eta != null && eta > 0) {
    final minutes = (eta / 60).round();
    return minutes <= 0 ? '곧 도착' : '약 $minutes분';
  }
  return arrival.message.trim();
}

String _arrivalDirectionLabel(RealtimeArrival arrival) {
  final direction = arrival.direction.trim();
  if (direction.isNotEmpty) {
    return direction;
  }
  final destination = arrival.destination.trim();
  return destination.isEmpty ? '' : '$destination 방면';
}

/// 주변역 패널의 도착 정보 영역. 실시간 스냅샷 상태에 따라 방향별 도착을
/// 표시하거나, 미지원·실패 시 "-" 대신 한 줄 안내를 보여준다.
class _SubwayArrivalPanel extends StatelessWidget {
  const _SubwayArrivalPanel({required this.snapshot});

  final RealtimeSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    switch (snapshot.status) {
      case RealtimeSnapshotStatus.loading:
        return const SizedBox(
          key: Key('networkMapNearbyArrivalLoading'),
          height: 46,
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      case RealtimeSnapshotStatus.unsupported:
      case RealtimeSnapshotStatus.unavailable:
        final message = snapshot.message.trim().isEmpty
            ? '실시간 도착 정보를 준비하고 있어요.'
            : snapshot.message.trim();
        return _SubwayArrivalNotice(message: message);
      case RealtimeSnapshotStatus.fresh:
      case RealtimeSnapshotStatus.stale:
        if (snapshot.arrivals.isEmpty) {
          return const _SubwayArrivalNotice(message: '표시할 도착 정보가 없어요.');
        }
        final groups = <String, List<RealtimeArrival>>{};
        for (final arrival in snapshot.arrivals) {
          groups.putIfAbsent(arrival.direction, () => []).add(arrival);
        }
        final directions = groups.keys.toList(growable: false);
        final left = groups[directions.first]!;
        final right = directions.length > 1
            ? groups[directions[1]]!
            : const <RealtimeArrival>[];
        final isStale = snapshot.status == RealtimeSnapshotStatus.stale;
        final semanticParts = <String>[
          for (final arrival in [...left, ...right])
            [
              _arrivalDirectionLabel(arrival),
              arrival.destination.trim().isEmpty
                  ? ''
                  : '${arrival.destination.trim()}행',
              _formatArrivalEta(arrival),
            ].where((part) => part.isNotEmpty).join(' '),
        ].where((part) => part.isNotEmpty).toList(growable: false);
        return Semantics(
          liveRegion: true,
          label: semanticParts.isEmpty ? '도착 정보 없음' : semanticParts.join(', '),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isStale) ...[
                Text(
                  snapshot.receivedAt.trim().isEmpty
                      ? '최근 도착 정보'
                      : '최근 도착 정보 · ${snapshot.receivedAt.trim()}',
                  style: const TextStyle(
                    color: EasySubwayAccessibleColors.mutedText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _SubwayArrivalColumn(arrivals: left)),
                  if (right.isNotEmpty) ...[
                    const SizedBox(
                      height: 46,
                      child: VerticalDivider(
                        color: Color(0xFFE0E0E0),
                        width: 30,
                      ),
                    ),
                    Expanded(child: _SubwayArrivalColumn(arrivals: right)),
                  ],
                ],
              ),
            ],
          ),
        );
    }
  }
}

class _SubwayArrivalNotice extends StatelessWidget {
  const _SubwayArrivalNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: EasySubwayAccessibleColors.mutedText,
            fontSize: 13,
            height: 1.3,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SubwayArrivalColumn extends StatelessWidget {
  const _SubwayArrivalColumn({required this.arrivals});

  final List<RealtimeArrival> arrivals;

  @override
  Widget build(BuildContext context) {
    final visible = arrivals.take(2).toList(growable: false);
    final directionLabel = visible.isEmpty
        ? ''
        : _arrivalDirectionLabel(visible.first);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (directionLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              directionLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        for (final arrival in visible) _SubwayArrivalRow(arrival: arrival),
      ],
    );
  }
}

class _SubwayArrivalRow extends StatelessWidget {
  const _SubwayArrivalRow({required this.arrival});

  final RealtimeArrival arrival;

  @override
  Widget build(BuildContext context) {
    final destination = arrival.destination.trim();
    final eta = _formatArrivalEta(arrival);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          if (destination.isNotEmpty)
            Text(
              '$destination행',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF2F2F2F),
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (eta.isNotEmpty)
            Text(
              eta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: EasySubwayAccessibleColors.secondaryText,
                fontSize: 12,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
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
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 52,
        width: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? EasySubwayAccessibleColors.mapRegionAccent
              : Colors.transparent,
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
    // 실광고 미연동: release에서는 "광고" 플레이스홀더를 노출하지 않고 슬롯을 숨긴다.
    return const SafeArea(
      top: false,
      child: AdBannerSlot(slotKey: Key('networkMapBottomAdBanner')),
    );
  }
}

class _NetworkMapMenuPanel extends StatelessWidget {
  const _NetworkMapMenuPanel({
    required this.onOpenStationSearch,
    required this.onOpenSavedItems,
    required this.onOpenNearbyStations,
    required this.onOpenServiceNotices,
    required this.onOpenSettings,
    required this.onOpenDataSources,
  });

  final VoidCallback onOpenStationSearch;
  final VoidCallback? onOpenSavedItems;
  final VoidCallback? onOpenNearbyStations;
  final VoidCallback? onOpenServiceNotices;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenDataSources;

  void _runAction(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  void _runActionAfterMenuClose(BuildContext context, VoidCallback action) {
    Navigator.of(context).pop();
    Future<void>.delayed(const Duration(milliseconds: 180), action);
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
          child: Column(
            children: [
              Expanded(
                child: SafeArea(
                  bottom: false,
                  child: ListView(
                    padding: EdgeInsets.zero,
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
                      // #1933 요구 3: 별도 길찾기 폼 페이지를 없앴다. 길찾기 진입은
                      // 노선도 역 탭(팝오버 출발/도착)·상단바 변신으로만 하므로,
                      // 폼으로 보내던 좌측 메뉴 "길찾기" 항목을 제거한다.
                      if (onOpenNearbyStations != null)
                        _NetworkMapMenuTile(
                          key: const Key('networkMapMenuNearbyButton'),
                          icon: Icons.near_me_outlined,
                          label: '가까운 역',
                          onTap: () =>
                              _runAction(context, onOpenNearbyStations!),
                        ),
                      if (onOpenSavedItems != null ||
                          onOpenSettings != null) ...[
                        const _NetworkMapMenuSectionLabel('내 정보'),
                        if (onOpenSavedItems != null)
                          _NetworkMapMenuTile(
                            key: const Key('networkMapMenuSavedButton'),
                            icon: Icons.star_border_rounded,
                            label: '즐겨찾기',
                            onTap: () => _runAction(context, onOpenSavedItems!),
                          ),
                        if (onOpenSettings != null)
                          _NetworkMapMenuTile(
                            key: const Key('networkMapMenuSettingsButton'),
                            icon: Icons.settings_outlined,
                            label: '설정',
                            onTap: () => _runAction(context, onOpenSettings!),
                          ),
                      ],
                      if (onOpenServiceNotices != null ||
                          onOpenDataSources != null) ...[
                        const _NetworkMapMenuSectionLabel('안내'),
                        if (onOpenServiceNotices != null)
                          _NetworkMapMenuTile(
                            key: const Key(
                              'networkMapMenuServiceNoticesButton',
                            ),
                            icon: Icons.campaign_outlined,
                            label: '운행 공지',
                            onTap: () =>
                                _runAction(context, onOpenServiceNotices!),
                          ),
                        if (onOpenDataSources != null)
                          _NetworkMapMenuTile(
                            key: const Key('networkMapMenuDataSourcesButton'),
                            icon: Icons.source_outlined,
                            label: '자료 제공 정보',
                            onTap: () => _runActionAfterMenuClose(
                              context,
                              onOpenDataSources!,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
              // 패널 최하단 고정 광고 슬롯(항목 스크롤과 분리, release는 collapse).
              const SafeArea(
                top: false,
                child: AdBannerSlot(slotKey: Key('networkMapMenuAdBanner')),
              ),
            ],
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
              color: EasySubwayAccessibleColors.listRowText,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
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
          color: EasySubwayAccessibleColors.caption,
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
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: EasySubwayAccessibleColors.mutedText,
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: EasySubwayAccessibleColors.listRowText,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: EasySubwayAccessibleColors.disclosure,
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

// 지도 datapack manifest(assets/datapacks/metro_map_pack/manifest.json)의
// license 블록에서 지역별 attribution 표기 문자열을 만든다(#1951). 하드코딩
// 지역 분기 대신 manifest의 `attributionRequired`를 정본으로 삼는다 —
// attributionRequired가 false면 해당 지역은 맵에서 제외한다.
const _mapManifestAssetPath = 'assets/datapacks/metro_map_pack/manifest.json';

@visibleForTesting
Map<String, String> parseNetworkMapAttributionByRegion(String manifestJson) {
  final manifest = jsonDecode(manifestJson) as Map<String, Object?>;
  final maps = (manifest['maps'] as List? ?? const [])
      .cast<Map<String, Object?>>();
  final result = <String, String>{};
  for (final map in maps) {
    final appRegion = map['app_region'] as String?;
    final license = map['license'] as Map<String, Object?>?;
    if (appRegion == null || license == null) {
      continue;
    }
    if (license['attributionRequired'] != true) {
      continue;
    }
    final authors = (license['authors'] as List? ?? const [])
        .whereType<Object>()
        .map((author) => '$author')
        .join(', ');
    final spdx = (license['spdx'] as String?)?.replaceAll('-', ' ').trim();
    final licenseLabel = (spdx != null && spdx.isNotEmpty)
        ? spdx
        : (license['name'] as String? ?? '');
    final text = [
      if (authors.isNotEmpty) authors,
      if (licenseLabel.isNotEmpty) licenseLabel,
    ].join(', ');
    if (text.isNotEmpty) {
      result[appRegion] = text;
    }
  }
  return result;
}

// manifest는 프로세스 생애주기 동안 바뀌지 않는 번들 asset이라, 노선도 canvas가
// 새로 마운트될 때마다(지역 전환 등) 매번 asset을 다시 읽지 않도록 모듈 캐시
// (_sharedAttributionTextByRegionFuture)로 1회만 로드해 공유한다. 로드 실패
// 시에는 캐시를 비워 다음 마운트에서 재시도한다(#1951).
Future<Map<String, String>>? _sharedAttributionTextByRegionFuture;

Future<Map<String, String>> _loadNetworkMapAttributionTextByRegion() {
  return _sharedAttributionTextByRegionFuture ??= rootBundle
      .loadString(_mapManifestAssetPath)
      .then(parseNetworkMapAttributionByRegion);
}

@visibleForTesting
void resetNetworkMapAttributionCacheForTest() {
  _sharedAttributionTextByRegionFuture = null;
}

class _NetworkMapCanvas extends StatefulWidget {
  const _NetworkMapCanvas({
    required this.data,
    required this.initialViewport,
    required this.focusedStationId,
    required this.selectedStationId,
    required this.onSetOrigin,
    required this.onSetWaypoint,
    required this.onSetDestination,
    required this.onClearOrigin,
    required this.onClearWaypoint,
    required this.onClearDestination,
    required this.onViewportChanged,
    required this.onSelectionDismissed,
    this.originStationId,
    this.waypointStationId,
    this.destinationStationId,
  });

  final NetworkMapData data;
  final Rect? initialViewport;
  final String? focusedStationId;
  final String? selectedStationId;

  /// #1948: draft 핀을 그릴 지정 역 id (없으면 null).
  final String? originStationId;
  final String? waypointStationId;
  final String? destinationStationId;

  final ValueChanged<NetworkMapStation> onSetOrigin;
  final ValueChanged<NetworkMapStation> onSetWaypoint;
  final ValueChanged<NetworkMapStation> onSetDestination;

  /// #2109: 팬 메뉴에서 이미 지정된 슬롯을 재탭하면 해당 슬롯을 비운다. clear는
  /// 슬롯 단위라 역 인자가 불필요(컨트롤러가 슬롯을 비운다).
  final VoidCallback onClearOrigin;
  final VoidCallback onClearWaypoint;
  final VoidCallback onClearDestination;
  final ValueChanged<Rect> onViewportChanged;

  /// #2109 팬 메뉴가 부모(검색 결과 탭 등)에서 [selectedStationId]로 열린 경우,
  /// 메뉴가 닫힐 때(액션 선택·닫기·배경 탭) 부모의 선택 상태도 비워야 한다.
  /// 내부 [_selectedStation]만 null로 두면 prop이 다시 메뉴를 띄운다.
  final VoidCallback onSelectionDismissed;

  @override
  State<_NetworkMapCanvas> createState() => _NetworkMapCanvasState();
}

const _minMapScale = 0.08;
const _maxMapScale = 4.8;

/// 역 focus 시 카메라 bounds를 지역 초기 화면(축소 하한, #1789) bounds의 이 비율로
/// 좁혀 항상 그만큼 확대되게 한다. 절대 픽셀 하한(구 860px) 대신 초기 화면 대비
/// 비율을 쓰는 이유: 수도권처럼 지도 폭이 작은 지역에서는 절대 하한이 초기 화면
/// 폭보다 커져 focus가 pan만 되고 확대가 사라졌다(#2062). 두 축을 같은 비율로
/// 줄이므로 contain-fit scale은 정확히 1/비율(≈2.38) 배 확대되어 지역 크기와
/// 무관하게 일정한 확대율을 보장한다 — 단, `_maxMapScale`(4.8) 상한 이하 범위
/// 한정. 초기 scale이 이미 4.8/0.42 ≈ 2.02를 넘는 초소형 지역(고배율 초기 화면)은
/// focus scale이 4.8에서 saturate돼 실제 확대율이 2.38배보다 작아지고, 초기
/// scale이 이미 4.8이면(초기 화면 자체가 상한에서 시작) focus도 4.8로 saturate돼
/// 확대율이 1.0(순수 pan)까지 줄어들 수 있다. 이 경우도 focus scale이 초기 scale
/// 아래로 내려가진 않는다(둘 다 같은 상한을 공유하므로) — pan-only로 완전히
/// 퇴행하진 않되, 극단적으로 작은 지역에서는 확대가 체감되지 않을 수 있다.
const _stationFocusInitialBoundsFraction = 0.42;
const _routeMapGestureRendererCommitInterval = Duration(milliseconds: 1100);
const _routeMapGestureMaxTranslationDriftFraction = 1.35;
const _routeMapGestureMaxScaleRatio = 3.4;
const _routeMapGestureRendererOverscanFactor = 3.25;

/// #1643 성능 QA: 노선도 프레임의 build/raster/total 시간을 logcat에 기록한다.
/// run-route-map-android-evidence.sh가 'routeMapFrame' 라인을 grep해 jank·P90를
/// 산출한다(Flutter는 dumpsys gfxinfo로 프레임이 안 잡혀 FrameTiming으로 계측).
void _logRouteMapFrameTimings(List<FrameTiming> timings) {
  for (final timing in timings) {
    final buildMs = timing.buildDuration.inMicroseconds / 1000.0;
    final rasterMs = timing.rasterDuration.inMicroseconds / 1000.0;
    final totalMs = timing.totalSpan.inMicroseconds / 1000.0;
    // debugPrint는 throttle(debugPrintThrottled)이라 pan 중 다량의 프레임 로그를
    // 큐잉·드롭해 janky burst 구간을 undercount할 수 있다(jank% 하향 편향). 측정
    // 정확도를 위해 unthrottled synchronous 출력으로 모든 프레임을 남긴다.
    debugPrintSynchronously(
      'routeMapFrame '
      'buildMs=${buildMs.toStringAsFixed(2)} '
      'rasterMs=${rasterMs.toStringAsFixed(2)} '
      'totalMs=${totalMs.toStringAsFixed(2)}',
    );
  }
}

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
  String? _geometryCacheKey;
  _MapGeometry? _geometryCache;
  // 구조화 canvas 렌더러(#1641) 파생 데이터 캐시 — region 단위로 재계산.
  String? _structuredCacheKey;
  StructuredRouteMap? _structuredRouteMapCache;
  Map<String, Color>? _structuredLineColorsCache;
  Map<String, String>? _structuredLabelTextCache;
  Map<String, String>? _structuredLineBadgeLabelCache;
  NetworkMapStation? _selectedStation;
  // region → attribution 표시 문자열(#1951). manifest 로드 전에는 null로 두고
  // attribution을 표시하지 않는다(로드 실패 시에도 동일하게 조용히 미표기).
  Map<String, String>? _attributionTextByRegion;
  // onTapUp 경로에서만 쓰는 stationLinesById를 매 build(팬 프레임)마다 재계산하지 않도록
  // region·stations identity로 캐시한다(#1973). 800역/24노선 재계산이 build 스파이크 원인.
  Map<String, List<NetworkMapLine>>? _stationLinesByIdCache;
  String? _stationLinesByIdCacheKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // #1643 성능 QA: 노선도가 떠 있는 동안 프레임 build/raster 시간을 logcat에
    // 기록한다. 구조화 canvas는 Flutter 자체 렌더 파이프라인이라 dumpsys gfxinfo로
    // 프레임이 잡히지 않으므로 FrameTiming으로 계측한다. release에는 넣지 않는다.
    if (!kReleaseMode) {
      SchedulerBinding.instance.addTimingsCallback(_logRouteMapFrameTimings);
    }
    _loadAttributionText();
  }

  Future<void> _loadAttributionText() async {
    try {
      final byRegion = await _loadNetworkMapAttributionTextByRegion();
      if (!mounted) {
        return;
      }
      setState(() => _attributionTextByRegion = byRegion);
    } catch (error, stackTrace) {
      // asset 로드/파싱 실패는 attribution 미표기로 폴백한다(#1951). 일시 오류가
      // 영구 미표기로 고정되지 않도록 실패한 Future는 캐시에서 비워 다음 마운트
      // 때 재시도되게 한다 — 화면은 죽지 않되, 원인 파악을 위해 예외는 리포터로
      // 남긴다.
      _sharedAttributionTextByRegionFuture = null;
      reportMobileError(
        error,
        stackTrace,
        context: '지도 datapack manifest에서 attribution 정보를 불러오는 중 예외가 발생했습니다.',
      );
    }
  }

  @override
  void dispose() {
    if (!kReleaseMode) {
      SchedulerBinding.instance.removeTimingsCallback(_logRouteMapFrameTimings);
    }
    WidgetsBinding.instance.removeObserver(this);
    _pendingCamera = null;
    super.dispose();
  }

  /// #2109 Fix: 검색 채널(인플레이스 `_focusStationFromSearch` + 풀페이지
  /// `focusStationRequestId` 소비)로 팬 메뉴가 [selectedStationId] prop을 통해
  /// 열릴 때도, 지도 탭(`_selectStation`)과 동일하게 화면 경계에서 메뉴가 잘리면
  /// 카메라를 최소 패닝해 전부 노출한다. prop이 null→역 id로 전이하는 순간을
  /// 감지해 카메라 focus가 확정되는 다음 프레임에 패닝을 예약한다.
  @override
  void didUpdateWidget(covariant _NetworkMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedId = widget.selectedStationId;
    if (selectedId != null && selectedId != oldWidget.selectedStationId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.selectedStationId != selectedId) {
          return;
        }
        final station = _stationById(widget.data.stations, selectedId);
        if (station != null) {
          _panCameraToRevealFanMenu(station);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('networkMapSurface'),
      decoration: const BoxDecoration(color: Colors.white),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = _geometryFor(widget.data);
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
            _routeMapRendererActive = widget.data.stations.isNotEmpty;
            _gestureActive = false;
            _cameraFocusedStationId = null;
            final initialCamera = _cameraForBounds(
              widget.initialViewport ?? geometry.initialBounds,
              constraints,
              sourceBounds: fullBounds,
              contain: true,
              minScale: minScale,
            );
            _camera = initialCamera;
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
          final originStation = _stationById(
            widget.data.stations,
            widget.originStationId,
          );
          final waypointStation = _stationById(
            widget.data.stations,
            widget.waypointStationId,
          );
          final destinationStation = _stationById(
            widget.data.stations,
            widget.destinationStationId,
          );
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
              // 역 focus 후에도 LOD 기준은 지역 초기 화면 baseline을 유지한다.
              initialScaleOverride: camera.initialScale,
            );
            _cameraFocusedStationId = focusedStation.id;
            _pendingCamera = null;
            _camera = focusedCamera;
            camera = focusedCamera;
            widget.onViewportChanged(focusedCamera.visibleSourceRect);
          } else if (focusedStation == null) {
            _cameraFocusedStationId = null;
          }
          return Stack(
            children: [
              Positioned.fill(
                child: !_routeMapRendererActive
                    ? const _OriginalRouteMapUnavailable()
                    : _buildStructuredRouteMapCanvas(camera, geometry.origin),
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
                            _clearSelectionAndNotify();
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
                          _stationLinesByIdCached(widget.data),
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
              if (!_gestureActive && originStation != null)
                _NetworkMapDraftPin(
                  key: const Key('networkMapDraftPin-origin'),
                  station: originStation,
                  geometry: geometry,
                  camera: camera,
                  label: '출발',
                  surfaceColor: EasySubwayAccessibleColors.primary,
                  semanticSuffix: '출발 지정됨',
                ),
              if (!_gestureActive && waypointStation != null)
                _NetworkMapDraftPin(
                  key: const Key('networkMapDraftPin-waypoint'),
                  station: waypointStation,
                  geometry: geometry,
                  camera: camera,
                  label: '경유',
                  surfaceColor: const Color(0xE8404445),
                  semanticSuffix: '경유 지정됨',
                ),
              if (!_gestureActive && destinationStation != null)
                _NetworkMapDraftPin(
                  key: const Key('networkMapDraftPin-destination'),
                  station: destinationStation,
                  geometry: geometry,
                  camera: camera,
                  label: '도착',
                  surfaceColor: EasySubwayAccessibleColors.primary,
                  semanticSuffix: '도착 지정됨',
                ),
              if (!_gestureActive && selectedStation != null)
                Builder(
                  builder: (context) {
                    final stationPoint = camera.sourceToViewportPoint(
                      Offset(
                        geometry.x(selectedStation),
                        geometry.y(selectedStation),
                      ),
                    );
                    // #2109: 배치 규칙은 fanMenuPlacement 단일 함수가 소유한다
                    // (카메라 최소 패닝 _panCameraToRevealFanMenu와 동일 규칙 소비).
                    final placement = fanMenuPlacement(
                      stationPoint: stationPoint,
                      viewport: Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      ),
                      clampPosition: true,
                    );
                    final left = placement.left;
                    final menuWidth = placement.menuWidth;
                    final top = placement.top;
                    final selectedSlots = fanMenuSelectedSlots(
                      stationId: selectedStation.id,
                      originStationId: widget.originStationId,
                      waypointStationId: widget.waypointStationId,
                      destinationStationId: widget.destinationStationId,
                    );
                    return Positioned(
                      key: const Key('networkMapStationSheet'),
                      left: left,
                      top: top,
                      width: menuWidth,
                      child: StationFanMenu(
                        width: menuWidth,
                        selectedSlots: selectedSlots,
                        disabledSlots: fanMenuDisabledSlots(
                          stationId: selectedStation.id,
                          originStationId: widget.originStationId,
                          waypointStationId: widget.waypointStationId,
                          destinationStationId: widget.destinationStationId,
                        ),
                        onAction: (slot) {
                          if (fanMenuShouldClear(slot, selectedSlots)) {
                            // 재탭 → 해당 슬롯 해제.
                            switch (slot) {
                              case RouteDraftSlot.origin:
                                widget.onClearOrigin();
                              case RouteDraftSlot.waypoint:
                                widget.onClearWaypoint();
                              case RouteDraftSlot.destination:
                                widget.onClearDestination();
                            }
                          } else {
                            switch (slot) {
                              case RouteDraftSlot.origin:
                                widget.onSetOrigin(selectedStation);
                              case RouteDraftSlot.waypoint:
                                widget.onSetWaypoint(selectedStation);
                              case RouteDraftSlot.destination:
                                widget.onSetDestination(selectedStation);
                            }
                          }
                          _dismissSelection();
                        },
                        onClose: _dismissSelection,
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Map<String, List<NetworkMapLine>> _stationLinesByIdCached(
    NetworkMapData data,
  ) {
    final key =
        '${data.selectedRegion}:${identityHashCode(data.stations)}:${data.stations.length}';
    final cached = _stationLinesByIdCache;
    if (_stationLinesByIdCacheKey == key && cached != null) {
      return cached;
    }
    final computed = _stationLinesById(data);
    _stationLinesByIdCacheKey = key;
    _stationLinesByIdCache = computed;
    return computed;
  }

  _MapGeometry _geometryFor(NetworkMapData data) {
    final cacheKey =
        'generated:${data.selectedRegion}:${identityHashCode(data.stations)}:${data.stations.length}';
    final cached = _geometryCache;
    if (_geometryCacheKey == cacheKey && cached != null) {
      return cached;
    }
    final geometry = _MapGeometry.fromStations(data.stations);
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

  /// 팬 메뉴를 닫는다: 내부 선택과 함께, prop([selectedStationId])으로 열린
  /// 경우 부모 선택 상태도 비우도록 알린다(그렇지 않으면 prop이 다시 띄운다).
  void _clearSelectionAndNotify() {
    _selectedStation = null;
    widget.onSelectionDismissed();
  }

  void _dismissSelection() => setState(_clearSelectionAndNotify);

  void _selectStation(NetworkMapStation station) {
    setState(() => _selectedStation = station);
    // #2109: 화면 경계에서 팬 메뉴가 잘리면 카메라를 최소 거리만 패닝해 전체
    // 노출한다. 다음 프레임(레이아웃 확정 후) 뷰포트 대비 메뉴 bbox를 계산한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedStation?.id != station.id) {
        return;
      }
      _panCameraToRevealFanMenu(station);
    });
  }

  void _panCameraToRevealFanMenu(NetworkMapStation station) {
    final camera = _pendingCamera ?? _camera;
    if (camera == null) {
      return;
    }
    final geometry = _geometryFor(widget.data);
    final stationPoint = camera.sourceToViewportPoint(
      Offset(geometry.x(station), geometry.y(station)),
    );
    const margin = kFanMenuViewportMargin;
    // #2109: 배치 bbox는 build와 동일하게 fanMenuPlacement가 계산한다
    // (규칙 중복 제거 — 한쪽만 바뀌어 패닝 bbox와 렌더 위치가 어긋나는 것 방지).
    // 패닝은 같은 viewport의 클램프 없는 이상적 배치로 최대한 노출을 시도하고,
    // 패닝이 .clamped() 한계로 다 못 드러내는 잔여는 build 경로의 viewport 클램프
    // 폴백이 처리한다.
    final menuRect = fanMenuPlacement(
      stationPoint: stationPoint,
      viewport: camera.viewportSize,
      clampPosition: false,
    ).revealBounds;
    final viewport = Offset.zero & camera.viewportSize;
    var dx = 0.0;
    var dy = 0.0;
    if (menuRect.left < viewport.left + margin) {
      dx = (viewport.left + margin) - menuRect.left;
    } else if (menuRect.right > viewport.right - margin) {
      dx = (viewport.right - margin) - menuRect.right;
    }
    if (menuRect.top < viewport.top + margin) {
      dy = (viewport.top + margin) - menuRect.top;
    } else if (menuRect.bottom > viewport.bottom - margin) {
      dy = (viewport.bottom - margin) - menuRect.bottom;
    }
    if (dx == 0 && dy == 0) {
      return;
    }
    // 뷰포트 픽셀 이동 → source 좌표 center 이동(반대 방향).
    final nextCenter = camera.center - Offset(dx, dy) / camera.scale;
    _setCamera(
      camera
          .copyWith(center: nextCenter, revision: camera.revision + 1)
          .clamped(),
    );
  }

  // 구조화 canvas 렌더러(#1641)를 visual camera로 마운트한다. WebView와 달리
  // 명령형 controller 없이 camera prop 변경(setState)으로 갱신된다.
  Widget _buildStructuredRouteMapCanvas(
    MapCameraState camera,
    Offset sourceOrigin,
  ) {
    _ensureStructuredRouteMap();
    return StructuredRouteMapView(
      map: _structuredRouteMapCache!,
      camera: camera,
      lineColors: _structuredLineColorsCache!,
      labelTextByStationId: _structuredLabelTextCache!,
      lineBadgeLabelByLineId: _structuredLineBadgeLabelCache!,
      sourceOrigin: sourceOrigin,
      attributionText: _attributionTextByRegion?[widget.data.selectedRegion],
    );
  }

  void _ensureStructuredRouteMap() {
    final data = widget.data;
    // geometry 캐시와 동일하게 identityHashCode를 포함해, 같은 region·같은 개수라도
    // data 인스턴스가 바뀌면(좌표 수정/노선 교체) 재계산되게 한다(overlay와 정합).
    final key =
        '${data.selectedRegion}:${identityHashCode(data.stations)}:${data.stations.length}:${data.lines.length}';
    if (_structuredCacheKey == key && _structuredRouteMapCache != null) {
      return;
    }
    _structuredCacheKey = key;
    _structuredRouteMapCache = data.toStructuredRouteMap();
    _structuredLineColorsCache = routeMapLineColors({
      for (final line in data.lines) line.id: line.color,
    });
    _structuredLabelTextCache = {
      for (final station in data.stations)
        station.id: routeMapStationLabel(station.nameKo),
    };
    _structuredLineBadgeLabelCache = {
      for (final line in data.lines) line.id: routeMapLineBadgeLabel(line.name),
    };
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
  // LOD 기준이 될 지역 baseline scale. null이면 이 카메라가 baseline이 되어
  // 자신의 fit scale을 쓴다(초기 카메라). focus/파생 카메라는 지역 초기
  // 카메라의 initialScale을 넘겨 baseline을 상속한다(#1764 A).
  double? initialScaleOverride,
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
      initialScale: initialScaleOverride ?? minScale,
    );
  }
  final widthScale = viewportWidth / bounds.width;
  final heightScale = viewportHeight / bounds.height;
  final computedScale = contain
      ? math.min(widthScale, heightScale)
      : math.max(widthScale, heightScale);
  final fitScale = computedScale.clamp(minScale, _maxMapScale).toDouble();
  return MapCameraState(
    sourceBounds: sourceBounds,
    viewportSize: Size(viewportWidth, viewportHeight),
    center: bounds.center,
    scale: fitScale,
    minScale: minScale,
    maxScale: _maxMapScale,
    revision: revision,
    initialScale: initialScaleOverride ?? fitScale,
  ).clamped(viewportMargin: 220);
}

/// 지역 초기 화면 카메라(contain-fit)를 만든다(테스트용). 이 카메라는
/// scale == initialScale 이라 지역 전체가 화면에 담긴 상태로 시작한다(#1789
/// 정적 스케일 렌더 — 초기 화면 = 축소 하한).
@visibleForTesting
MapCameraState networkMapInitialCameraForRegion({
  required Rect regionBounds,
  required Rect fullBounds,
  required Size viewport,
}) {
  return _cameraForBounds(
    regionBounds,
    BoxConstraints.tightFor(width: viewport.width, height: viewport.height),
    sourceBounds: fullBounds,
    contain: true,
  );
}

/// 역 focus 카메라(contain-fit)를 만든다(테스트용). 프로덕션 focus 분기와 같은
/// bounds 규칙([_stationFocusBounds])·같은 [_cameraForBounds] contain-fit을 써서
/// focus가 지역 초기 화면보다 확대되는지 회귀 테스트가 가드하게 한다(#2062).
@visibleForTesting
MapCameraState networkMapStationFocusCameraForRegion({
  required Rect initialBounds,
  required Offset stationCenter,
  required Rect fullBounds,
  required Size viewport,
  double? initialScaleOverride,
}) {
  return _cameraForBounds(
    _stationFocusBounds(
      initialBounds: initialBounds,
      center: stationCenter,
      sourceWidth: fullBounds.width,
      sourceHeight: fullBounds.height,
    ),
    BoxConstraints.tightFor(width: viewport.width, height: viewport.height),
    sourceBounds: fullBounds,
    contain: true,
    initialScaleOverride: initialScaleOverride,
  );
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

/// 이 역 수(route_map_positions 행) 이하 지역은 초기 화면에 지역 전체를 담는다
/// (소규모 tight-fit, #1764 E). 광주·대전급(수십 역)은 소규모, 부산·대구·수도권급
/// (백 역 이상)은 대형. 임계 40은 소규모(~20)와 대형(100+) 사이 넓은 간극에 둔다.
const int _smallRegionStationCountThreshold = 40;

/// 초기 화면에 지역 전체를 담는(소규모 tight-fit) 지역인지(#1764 E). 이 역 수
/// 이하면 38% 도심 확대 대신 전체 조망으로 시작한다(광주·대전=true).
@visibleForTesting
bool networkMapUsesWholeRegionInitialView(int stationCount) =>
    stationCount <= _smallRegionStationCountThreshold;

Rect _readableBoundsFor(_MapGeometry geometry, {required int stationCount}) {
  // 소규모 지역은 38% 도심 확대 대신 지역 전체를 초기 viewport로 둬 과확대를
  // 막는다(초기 화면=bucket 1에서 전 역·환승/주요 라벨이 보이도록, #1764 E).
  // 판정은 networkMapUsesWholeRegionInitialView 단일 소스를 쓴다(테스트가 실제
  // 렌더 분기를 가드하도록).
  if (networkMapUsesWholeRegionInitialView(stationCount)) {
    return Rect.fromLTWH(0, 0, geometry.width, geometry.height);
  }
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
  return _stationFocusBounds(
    initialBounds: geometry.initialBounds,
    center: Offset(geometry.x(station), geometry.y(station)),
    sourceWidth: geometry.width,
    sourceHeight: geometry.height,
  );
}

/// 역 focus 카메라의 source bounds를 계산한다. 지역 초기 화면 bounds를
/// [_stationFocusInitialBoundsFraction]만큼 두 축 동일 비율로 좁혀 focus가 항상
/// 초기 화면보다 확대되도록 한다(#2062). 좁힌 bounds가 지도 크기를 넘지 않도록만
/// clamp하며(focus는 항상 초기 화면보다 작으므로 실제로는 걸리지 않음), edge 역은
/// _sourceCenteredBounds가 지도 안으로 이동시킨다.
Rect _stationFocusBounds({
  required Rect initialBounds,
  required Offset center,
  required double sourceWidth,
  required double sourceHeight,
}) {
  final width = math.min(
    sourceWidth,
    initialBounds.width * _stationFocusInitialBoundsFraction,
  );
  final height = math.min(
    sourceHeight,
    initialBounds.height * _stationFocusInitialBoundsFraction,
  );
  return _sourceCenteredBounds(
    center: center,
    width: width,
    height: height,
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
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
      initialBounds: _readableBoundsFor(
        geometry,
        stationCount: stations.length,
      ),
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

/// 역 tap hit target 한 변 길이(logical px). 노드 중심에서 사방
/// [_maximumStationHitDistance]까지 tap을 받으므로 hit rect 한 변은 그 2배다.
/// AGENTS.md 큰 터치 영역 hard rule + WCAG 2.5.5(target size 최소 48×48)를
/// 노선도 역 선택에 보장한다 — #1642 접근성 회귀 가드.
@visibleForTesting
const double networkMapStationHitTargetLogicalSize =
    _maximumStationHitDistance * 2;

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
    // 노출 상수를 단일 소스로 써서, 48dp 접근성 회귀 가드 테스트가 실제 hit
    // rect를 지키게 한다(상수와 rect의 독립 재유도 드리프트 방지).
    width: networkMapStationHitTargetLogicalSize,
    height: networkMapStationHitTargetLogicalSize,
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

/// #1948: 상단바 draft 필드의 종류. 출발/도착에 더해 경유(2단계 경유역)를
/// 같은 무채색 채움 필드 리듬으로 표시한다.
enum _RouteDraftFieldKind { origin, waypoint, destination }

/// #1933 요구 2: 출발/도착이 하나라도 차면 상단바 "자체"가 참고 앱 OD 입력
/// 구조(출발/도착 각각을 무채색 채움 필드 2개로 표시)로 변신한다. 아래 별도
/// 카드를 띄우지 않는다 — 그림자/elevation 0, 라운딩은 8 이하, splash 없이
/// 채움 색과 여백만으로 depth를 준다. 무채색 잉크만.
class _NetworkMapTopBarRouteDraft extends StatelessWidget {
  const _NetworkMapTopBarRouteDraft({
    required this.draft,
    required this.onClearOrigin,
    required this.onClearDestination,
    required this.onClearWaypoint,
    required this.onSwapDraft,
    required this.onReorderDraft,
    this.onPickOrigin,
    this.onPickDestination,
    this.onPickWaypoint,
    super.key,
  });

  final RouteDraft draft;
  final VoidCallback onClearOrigin;
  final VoidCallback onClearDestination;
  final VoidCallback onClearWaypoint;
  final VoidCallback onSwapDraft;

  /// #1985: draft 행 드래그 재배열 콜백. (from, to) 슬롯 쌍을 넘긴다.
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorderDraft;

  /// G4: 각 칸 탭 → 역 검색 열기(같은 draft로 수렴). null이면 칸을 탭할 수 없다.
  final VoidCallback? onPickOrigin;
  final VoidCallback? onPickDestination;

  /// #1948: 경유역 채우기(경유 행 탭·경유 추가 진입점). null이면 경유를 추가할 수 없다.
  final VoidCallback? onPickWaypoint;

  @override
  Widget build(BuildContext context) {
    final canSwap = draft.origin != null || draft.destination != null;
    // #1985: 현재 렌더 중인 행 슬롯 순서. 경유가 있으면 출발·경유·도착 3행.
    final visibleSlots = <RouteDraftSlot>[
      RouteDraftSlot.origin,
      if (draft.waypoint != null) RouteDraftSlot.waypoint,
      RouteDraftSlot.destination,
    ];
    // 각 행이 이동할 수 있는 다른 슬롯 목록(자기 자신 제외).
    List<RouteDraftSlot> targetsFor(RouteDraftSlot slot) =>
        visibleSlots.where((s) => s != slot).toList();
    // 출발/도착 2개의 무채색 채움 필드. TalkBack 순서: 출발 먼저, 도착.
    // 행 리스트로 렌더해 중간 행 확장이 구조 변경 없이 가능하다.
    final fields = <Widget>[
      _NetworkMapRouteDraftField(
        kind: _RouteDraftFieldKind.origin,
        slot: RouteDraftSlot.origin,
        station: draft.origin,
        onClear: onClearOrigin,
        onPick: onPickOrigin,
        reorderTargets: targetsFor(RouteDraftSlot.origin),
        onReorder: onReorderDraft,
      ),
      // #1948: 경유가 있으면 출발과 도착 사이에 경유 행을 삽입한다.
      if (draft.waypoint != null)
        _NetworkMapRouteDraftField(
          kind: _RouteDraftFieldKind.waypoint,
          slot: RouteDraftSlot.waypoint,
          station: draft.waypoint,
          onClear: onClearWaypoint,
          onPick: onPickWaypoint,
          reorderTargets: targetsFor(RouteDraftSlot.waypoint),
          onReorder: onReorderDraft,
        ),
      _NetworkMapRouteDraftField(
        kind: _RouteDraftFieldKind.destination,
        slot: RouteDraftSlot.destination,
        station: draft.destination,
        onClear: onClearDestination,
        onPick: onPickDestination,
        reorderTargets: targetsFor(RouteDraftSlot.destination),
        onReorder: onReorderDraft,
      ),
    ];
    // #1948: 경유는 출발·도착 한 쌍이 정해진 뒤에 더하는 옵션이다. 출발/도착이
    // 모두 차 있고 아직 경유가 없으며 추가가 가능할 때만 '경유 추가' 어포던스를
    // 필드 아래 둔다(출발만 정한 중간 상태에서는 노출하지 않는다).
    final showAddWaypoint =
        draft.origin != null &&
        draft.destination != null &&
        draft.waypoint == null &&
        onPickWaypoint != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 10, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 출발/도착 맞바꾸기(⇅). 참고 앱 상단 입력바의 스왑 어포던스와 같은 원리.
          Semantics(
            button: true,
            enabled: canSwap,
            label: '출발 도착 바꾸기',
            onTap: canSwap ? onSwapDraft : null,
            child: ExcludeSemantics(
              child: IconButton(
                key: const Key('networkMapRouteDraftSwap'),
                tooltip: '출발 도착 바꾸기',
                onPressed: canSwap ? onSwapDraft : null,
                icon: const Icon(Icons.swap_vert, size: 22),
                color: EasySubwayAccessibleColors.mutedText,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 6),
                  fields[i],
                ],
                if (showAddWaypoint) ...[
                  const SizedBox(height: 6),
                  _NetworkMapRouteDraftAddWaypoint(onTap: onPickWaypoint!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// #1948: 경유가 없을 때 노출되는 '경유 추가' 어포던스. 무채색·radius 8·splash
/// 없음·터치 타깃 48. 탭 시 경유역 검색을 연다.
class _NetworkMapRouteDraftAddWaypoint extends StatelessWidget {
  const _NetworkMapRouteDraftAddWaypoint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '경유역 추가',
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const Key('networkMapRouteDraftAddWaypoint'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: EasySubwayAccessibleColors.scaffoldSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Icon(
                  Icons.add,
                  size: 18,
                  color: EasySubwayAccessibleColors.mutedText,
                ),
                const SizedBox(width: 8),
                Text(
                  '경유 추가',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: EasySubwayAccessibleColors.mutedText,
                    fontWeight: FontWeight.w700,
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

/// 변신한 상단바의 한 줄(출발 또는 도착) — 무채색 채움 필드. 라운딩 8 이하,
/// 그림자/elevation 없음, splash 없음(GestureDetector만 사용). 채워졌을
/// 때만 지우기(✕) 버튼을 보인다.
class _NetworkMapRouteDraftField extends StatelessWidget {
  const _NetworkMapRouteDraftField({
    required this.kind,
    required this.slot,
    required this.station,
    required this.onClear,
    required this.reorderTargets,
    required this.onReorder,
    this.onPick,
  });

  final _RouteDraftFieldKind kind;

  /// #1985: 이 행이 대응하는 draft 슬롯. 드래그 재배열의 from/to 계산에 쓴다.
  final RouteDraftSlot slot;
  final RouteDraftStation? station;
  final VoidCallback onClear;

  /// #1985: 이 행에서 옮겨 갈 수 있는 다른 슬롯들(현재 렌더 중인 다른 행들).
  final List<RouteDraftSlot> reorderTargets;

  /// #1985: 드래그·시맨틱 액션이 호출하는 재배열 콜백. (from, to) 슬롯을 넘긴다.
  final void Function(RouteDraftSlot from, RouteDraftSlot to) onReorder;

  /// G4: 이 칸(역명/플레이스홀더 영역)을 탭하면 역 검색을 연다. null이면 탭 불가.
  final VoidCallback? onPick;

  String get _label => switch (kind) {
    _RouteDraftFieldKind.origin => '출발',
    _RouteDraftFieldKind.waypoint => '경유',
    _RouteDraftFieldKind.destination => '도착',
  };

  /// #1985: 빈 행 placeholder 표시·낭독 문구('출발역'/'경유역'/'도착역').
  String get _placeholderLabel => slot.displayLabel;

  String get _searchLabel => '${slot.displayLabel} 검색';

  String get _rowKey => switch (kind) {
    _RouteDraftFieldKind.origin => 'networkMapRouteDraftOriginRow',
    _RouteDraftFieldKind.waypoint => 'networkMapRouteDraftWaypointRow',
    _RouteDraftFieldKind.destination => 'networkMapRouteDraftDestinationRow',
  };

  String get _pickKey => switch (kind) {
    _RouteDraftFieldKind.origin => 'networkMapRouteDraftPickOrigin',
    _RouteDraftFieldKind.waypoint => 'networkMapRouteDraftPickWaypoint',
    _RouteDraftFieldKind.destination => 'networkMapRouteDraftPickDestination',
  };

  String get _clearKey => switch (kind) {
    _RouteDraftFieldKind.origin => 'networkMapRouteDraftClearOrigin',
    _RouteDraftFieldKind.waypoint => 'networkMapRouteDraftClearWaypoint',
    _RouteDraftFieldKind.destination => 'networkMapRouteDraftClearDestination',
  };

  @override
  Widget build(BuildContext context) {
    final label = _label;
    final filled = station != null;
    // #1985: 빈 행은 placeholder 문구('출발역'/'경유역'/'도착역')를 표시한다.
    final stationName = filled ? station!.displayName : _placeholderLabel;
    // 접근성: 검색 진입 라벨을 "출발역 검색"/"경유역 검색"/"도착역 검색"으로 낭독한다.
    final searchLabel = _searchLabel;
    // #1985: 빈 행은 '역역' 중복을 피하려 검색 라벨(예: '출발역 검색')만 낭독한다.
    final pickSemanticsLabel = filled
        ? '$label $stationName, $searchLabel'
        : searchLabel;
    final textRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            stationName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: filled
                  ? EasySubwayAccessibleColors.text
                  : EasySubwayAccessibleColors.mutedText,
            ),
          ),
        ),
      ],
    );
    // 역명/플레이스홀더 영역: onPick이 있으면 검색을 여는 버튼. 없으면 정보 표시만.
    final Widget pickArea = onPick == null
        ? Semantics(
            // #1985: 빈 행은 '역역' 중복을 피하려 placeholder 문구만 낭독한다.
            label: filled ? '$label $stationName' : _placeholderLabel,
            child: ExcludeSemantics(child: textRow),
          )
        : Semantics(
            button: true,
            label: pickSemanticsLabel,
            onTap: onPick,
            child: ExcludeSemantics(
              // 탭 시 요란한 splash/highlight 사각형을 남기지 않는다(#1933 원칙).
              // 입력 필드처럼 보이되 조용히 역 검색으로 전환.
              child: GestureDetector(
                key: Key(_pickKey),
                behavior: HitTestBehavior.opaque,
                onTap: onPick,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(child: textRow),
                ),
              ),
            ),
          );
    final rowContainer = Container(
      constraints: const BoxConstraints(minHeight: 54),
      decoration: BoxDecoration(
        color: EasySubwayAccessibleColors.scaffoldSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: pickArea),
            if (filled)
              Semantics(
                button: true,
                label: '$label역 지우기',
                onTap: onClear,
                child: ExcludeSemantics(
                  child: IconButton(
                    key: Key(_clearKey),
                    onPressed: onClear,
                    // 작은 원형 배지형 지우기(✕) — 무채색. 탭 시 요란한
                    // splash/highlight 사각형을 남기지 않는다(#1933 원칙).
                    style: IconButton.styleFrom(
                      splashFactory: NoSplash.splashFactory,
                      highlightColor: Colors.transparent,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                    ),
                    icon: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: EasySubwayAccessibleColors.disclosure,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // #1985: 채워진 행만 드래그로 재배열할 수 있다. 빈 행은 드래그 소스를 두지
    // 않고 이동 대상(DragTarget)으로만 쓴다.
    Widget content = rowContainer;
    if (filled) {
      content = LongPressDraggable<RouteDraftSlot>(
        data: slot,
        maxSimultaneousDrags: 1,
        dragAnchorStrategy: childDragAnchorStrategy,
        // 드래그 피드백: 무채색·radius 8·elevation 0·그림자 없음(#1933 원칙 유지).
        feedback: Material(
          elevation: 0,
          type: MaterialType.transparency,
          child: SizedBox(
            width: 220,
            child: Container(
              constraints: const BoxConstraints(minHeight: 54),
              decoration: BoxDecoration(
                color: EasySubwayAccessibleColors.scaffoldSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                station!.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                ),
              ),
            ),
          ),
        ),
        // 드래그 중 원래 행은 무채색으로 흐리게(노선색/틴트 없음).
        childWhenDragging: Opacity(opacity: 0.4, child: rowContainer),
        child: rowContainer,
      );
      // 커스텀 시맨틱 액션: 각 대상 슬롯으로 '~으로 이동'. child 트리 밖 wrapper라
      // 별도 SemanticsNode로 병합된다.
      content = Semantics(
        container: true,
        customSemanticsActions: <CustomSemanticsAction, VoidCallback>{
          for (final target in reorderTargets)
            CustomSemanticsAction(label: '${target.displayLabel}으로 이동'): () =>
                onReorder(slot, target),
        },
        child: content,
      );
    }

    // 모든 행(빈 행 포함)이 이동 대상이 된다. 행 키는 최상위 DragTarget에 둔다.
    return DragTarget<RouteDraftSlot>(
      key: Key(_rowKey),
      onWillAcceptWithDetails: (details) => details.data != slot,
      onAcceptWithDetails: (details) => onReorder(details.data, slot),
      builder: (context, candidateData, rejectedData) => content,
    );
  }
}

/// #1948: 출발/경유/도착으로 지정된 역 위에 말풍선형 draft 핀을 표시한다.
class _NetworkMapDraftPin extends StatelessWidget {
  const _NetworkMapDraftPin({
    super.key,
    required this.station,
    required this.geometry,
    required this.camera,
    required this.label,
    required this.surfaceColor,
    required this.semanticSuffix,
  });

  final NetworkMapStation station;
  final _MapGeometry geometry;
  final MapCameraState camera;
  final String label;
  final Color surfaceColor;
  final String semanticSuffix;

  @override
  Widget build(BuildContext context) {
    final stationPoint = camera.sourceToViewportPoint(
      Offset(geometry.x(station), geometry.y(station)),
    );
    const width = 72.0;
    const height = 40.0;
    final viewportWidth = camera.viewportSize.width;
    final left = (stationPoint.dx - width / 2)
        .clamp(12.0, math.max(12.0, viewportWidth - width - 12))
        .toDouble();
    final top = math.max(12.0, stationPoint.dy - height - 14);
    final arrowLeft = (stationPoint.dx - left - 11).clamp(4.0, width - 26);
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Semantics(
        container: true,
        label: '${station.displayName}, $semanticSuffix',
        child: ExcludeSemantics(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                color: surfaceColor,
                elevation: 0,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: arrowLeft),
                  child: Icon(
                    Icons.arrow_drop_down,
                    size: 22,
                    color: surfaceColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// #2109 팬 메뉴 배치 결과. build 경로(라벨·메뉴 Positioned)와 카메라 최소
/// 패닝(_panCameraToRevealFanMenu)이 같은 규칙을 소비하도록 단일 함수로 계산한다.
/// 두 경로가 배치식을 각각 하드코딩하면 한쪽만 바뀌었을 때 패닝 bbox와 실제
/// 렌더 위치가 어긋난다.
/// 팬 메뉴가 지도 소스 경계 등으로 카메라 패닝만으로 다 드러나지 않을 때, 배치
/// 함수가 화면 안으로 클램프할 여백. 카메라 최소 패닝(_panCameraToRevealFanMenu)의
/// margin과 동일 값이라 두 경로가 같은 여백을 본다.
const double kFanMenuViewportMargin = 12.0;

class FanMenuPlacement {
  const FanMenuPlacement({
    required this.placeBelow,
    required this.left,
    required this.top,
    required this.menuWidth,
    required this.menuHeight,
    required this.revealBounds,
  });

  /// 위쪽 공간이 부족해 메뉴를 노드 아래로 뒤집었는지.
  final bool placeBelow;

  /// 팬 메뉴 Positioned의 left/top.
  final double left;
  final double top;
  final double menuWidth;
  final double menuHeight;

  /// 화면 안에 들여야 하는 팬 메뉴 뷰포트 bbox(카메라 패닝 대상).
  final Rect revealBounds;
}

/// 역 노드의 뷰포트 좌표([stationPoint])로 팬 메뉴 배치를 계산한다.
/// 기본은 노드 위쪽에 메뉴 하단(닫기 노치)이 오도록 배치하되, 지도 상단 경계에
/// 붙은 역은 위쪽 공간이 부족하므로 노드 아래로 뒤집어 항상 화면 안에 들어오게
/// 한다(#2109).
///
/// 렌더와 카메라 패닝이 같은 viewport 기반 메뉴 크기를 사용한다. 렌더 경로는
/// [clampPosition]을 켜 극단 경계에서도 메뉴를 화면 안에 두고, 카메라 경로는
/// 끈 이상적 배치의 [FanMenuPlacement.revealBounds]를 노출 대상으로 사용한다.
@visibleForTesting
double fanMenuWidthForViewport(double viewportWidth) => math.min(
  260.0,
  math.max(0.0, viewportWidth - (kFanMenuViewportMargin * 2)),
);

@visibleForTesting
FanMenuPlacement fanMenuPlacement({
  required Offset stationPoint,
  required Size viewport,
  required bool clampPosition,
}) {
  final menuWidth = fanMenuWidthForViewport(viewport.width);
  final menuHeight =
      menuWidth * (kFanMenuDesignSize.height / kFanMenuDesignSize.width);
  var left = stationPoint.dx - menuWidth / 2;
  final placeBelow = stationPoint.dy - menuHeight - 8 < 8;
  var top = placeBelow
      ? stationPoint.dy + 28
      : stationPoint.dy - menuHeight - 8;
  if (clampPosition) {
    const margin = kFanMenuViewportMargin;
    final maxLeft = viewport.width - margin - menuWidth;
    if (maxLeft >= margin) {
      left = left.clamp(margin, maxLeft).toDouble();
    }
    final maxTop = viewport.height - margin - menuHeight;
    if (maxTop >= margin) {
      top = top.clamp(margin, maxTop).toDouble();
    }
  }
  return FanMenuPlacement(
    placeBelow: placeBelow,
    left: left,
    top: top,
    menuWidth: menuWidth,
    menuHeight: menuHeight,
    revealBounds: Rect.fromLTWH(left, top, menuWidth, menuHeight),
  );
}

/// 팬 메뉴 배선용: 탭한 역이 이미 배정된 슬롯 집합(진한 채움 selected).
@visibleForTesting
Set<RouteDraftSlot> fanMenuSelectedSlots({
  required String stationId,
  required String? originStationId,
  required String? waypointStationId,
  required String? destinationStationId,
}) {
  return {
    if (stationId == originStationId) RouteDraftSlot.origin,
    if (stationId == waypointStationId) RouteDraftSlot.waypoint,
    if (stationId == destinationStationId) RouteDraftSlot.destination,
  };
}

/// 팬 메뉴 배선용: 탭한 섹터의 슬롯을 재탭(해제)할지 신규 배정할지 판정.
/// 탭한 역이 이미 그 슬롯에 배정돼 있으면([selectedSlots]에 포함) 재탭으로
/// 간주해 true(해제)를, 아니면 false(신규 배정)를 반환한다.
@visibleForTesting
bool fanMenuShouldClear(
  RouteDraftSlot slot,
  Set<RouteDraftSlot> selectedSlots,
) {
  return selectedSlots.contains(slot);
}

/// 팬 메뉴 배선용: 같은 역이 다른 슬롯에 이미 있어 dim할 슬롯 집합.
/// 구 액션 오버레이의 originEnabled/waypointEnabled/destinationEnabled 규칙을
/// 그대로 이식(자기 슬롯 재지정은 dim 아님).
@visibleForTesting
Set<RouteDraftSlot> fanMenuDisabledSlots({
  required String stationId,
  required String? originStationId,
  required String? waypointStationId,
  required String? destinationStationId,
}) {
  final originEnabled =
      stationId != waypointStationId && stationId != destinationStationId;
  final waypointEnabled =
      stationId != originStationId && stationId != destinationStationId;
  final destinationEnabled =
      stationId != originStationId && stationId != waypointStationId;
  return {
    if (!originEnabled) RouteDraftSlot.origin,
    if (!waypointEnabled) RouteDraftSlot.waypoint,
    if (!destinationEnabled) RouteDraftSlot.destination,
  };
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
