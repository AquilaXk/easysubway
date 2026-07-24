import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../app/easy_subway_family_app_bar.dart';
import '../../../core/external/kakao_map_launcher.dart';
import '../../../facility_report.dart';
import '../../../internal_route.dart';
import '../../ads/ad_repository.dart';
import '../../realtime/realtime_repository.dart';
import '../../route_draft/application/route_draft_controller.dart';
import '../application/station_detail_controller.dart';
import '../domain/station_line.dart';
import '../domain/station_repositories.dart';
import 'station_detail_body.dart';
import 'station_line_badges.dart';

/// 검색·즐겨찾기용 거의 전체 높이 모달 시트. 본문은 [StationDetailScreen]/[StationDetailBody].
Future<T?> showStationDetailSheet<T>({
  required BuildContext context,
  required StationSearchRepository repository,
  required FacilityReportRepository reportRepository,
  required String stationId,
  FavoriteStationRepository? favoriteRepository,
  AdRepository? adRepository,
  RealtimeRepository? realtimeRepository,
  CurrentLocationProvider? locationProvider,
  bool? initiallyFavorite,
  FacilityReportDraftTargetStore? facilityReportDraftTargetStore,
  InternalRouteRepository? internalRouteRepository,
  InternalRouteRequest? internalRouteRequest,
  String internalRouteMobilityType = 'SENIOR',
  RouteDraftController? routeDraftController,
  KakaoMapLauncher mapLauncher = const UrlLauncherKakaoMapLauncher(),
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: EasySubwayAccessibleColors.surface,
    builder: (sheetContext) {
      final height = MediaQuery.sizeOf(sheetContext).height;
      return SizedBox(
        key: const Key('stationDetailSheet'),
        height: height * 0.95,
        child: StationDetailScreen(
          repository: repository,
          reportRepository: reportRepository,
          favoriteRepository: favoriteRepository,
          adRepository: adRepository,
          realtimeRepository: realtimeRepository,
          locationProvider: locationProvider,
          stationId: stationId,
          initiallyFavorite: initiallyFavorite,
          facilityReportDraftTargetStore: facilityReportDraftTargetStore,
          internalRouteRepository: internalRouteRepository,
          internalRouteRequest: internalRouteRequest,
          internalRouteMobilityType: internalRouteMobilityType,
          routeDraftController: routeDraftController,
          mapLauncher: mapLauncher,
        ),
      );
    },
  );
}

class StationDetailScreen extends StatefulWidget {
  const StationDetailScreen({
    required this.repository,
    required this.reportRepository,
    required this.stationId,
    this.favoriteRepository,
    this.adRepository,
    this.realtimeRepository,
    this.locationProvider,
    this.initiallyFavorite,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteRequest,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    this.mapLauncher = const UrlLauncherKakaoMapLauncher(),
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final FavoriteStationRepository? favoriteRepository;
  final AdRepository? adRepository;
  final RealtimeRepository? realtimeRepository;
  final CurrentLocationProvider? locationProvider;
  final String stationId;
  final bool? initiallyFavorite;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final InternalRouteRequest? internalRouteRequest;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;
  final KakaoMapLauncher mapLauncher;

  @override
  State<StationDetailScreen> createState() => _StationDetailScreenState();
}

class _StationDetailScreenState extends State<StationDetailScreen> {
  late final StationDetailController _controller;
  StationFavoriteToggleController? _favoriteController;
  InternalRouteController? _internalRouteController;

  @override
  void initState() {
    super.initState();
    _controller = StationDetailController(
      repository: widget.repository,
      realtimeRepository: widget.realtimeRepository,
    );
    final internalRouteRepository = widget.internalRouteRepository;
    final internalRouteRequest = widget.internalRouteRequest;
    if (internalRouteRepository != null) {
      _internalRouteController = InternalRouteController(
        repository: internalRouteRepository,
      );
      if (internalRouteRequest != null) {
        _internalRouteController!.load(internalRouteRequest);
      } else {
        _internalRouteController!.loadDefault(
          stationId: widget.stationId,
          mobilityType: widget.internalRouteMobilityType,
        );
      }
    }
    final favoriteRepository = widget.favoriteRepository;
    if (favoriteRepository != null) {
      final initiallyFavorite = widget.initiallyFavorite;
      _favoriteController = StationFavoriteToggleController(
        repository: favoriteRepository,
        stationId: widget.stationId,
        initiallyFavorite: initiallyFavorite ?? false,
        initiallyChecking: initiallyFavorite == null,
      );
      if (initiallyFavorite == null) {
        _favoriteController!.load();
      }
    }
    _controller.load(widget.stationId);
  }

  @override
  void dispose() {
    _controller.dispose();
    _favoriteController?.dispose();
    _internalRouteController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, ?_internalRouteController]),
      builder: (context, _) {
        return Scaffold(
          backgroundColor: EasySubwayAccessibleColors.surface,
          appBar: EasySubwayFamilyAppBar(
            key: const Key('stationDetailAppBar'),
            title: _StationDetailAppBarTitle(state: _controller.state),
            backButtonKey: const Key('stationDetailBackButton'),
            dividerKey: const Key('stationDetailHeaderDivider'),
          ),
          body: Semantics(
            container: true,
            child: SafeArea(
              child: StationDetailBody(
                state: _controller.state,
                onRetryRealtime: _controller.retryRealtime,
                internalRouteState: _internalRouteController?.state,
                reportRepository: widget.reportRepository,
                favoriteController: _favoriteController,
                adRepository: widget.adRepository,
                routeDraftController: widget.routeDraftController,
                locationProvider: widget.locationProvider,
                mapLauncher: widget.mapLauncher,
                facilityReportDraftTargetStore:
                    widget.facilityReportDraftTargetStore,
                timetableRepository:
                    widget.repository is StationTimetableRepository
                    ? widget.repository as StationTimetableRepository
                    : null,
                // AppBar가 호선·역명을 담당. 이전/다음역 chrome은 노선도 확장(PR-B)에서.
                showContextChrome: false,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StationDetailAppBarTitle extends StatelessWidget {
  const _StationDetailAppBarTitle({required this.state});

  final StationDetailState state;

  @override
  Widget build(BuildContext context) {
    final detail = state.detail;
    if (state.status != StationDetailStatus.success || detail == null) {
      return const Text('역 상세');
    }

    final primaryLine = detail.lines.isEmpty ? null : detail.lines.first;

    return Semantics(
      // 본문 헤더를 없애므로 상세 요약 시맨틱을 AppBar 타이틀에 둔다.
      label: detail.semanticLabel,
      header: true,
      child: ExcludeSemantics(
        child: Row(
          children: [
            if (primaryLine != null) ...[
              StationLineBadge(line: primaryLine, size: 28),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                '${detail.nameKo}역',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 노선도 하단 패널 확장용 Host. Family AppBar 없이 [StationDetailBody]만 소유한다.
class StationDetailExpandHost extends StatefulWidget {
  const StationDetailExpandHost({
    required this.repository,
    required this.reportRepository,
    required this.stationId,
    this.favoriteRepository,
    this.adRepository,
    this.realtimeRepository,
    this.locationProvider,
    this.initiallyFavorite,
    this.facilityReportDraftTargetStore,
    this.internalRouteRepository,
    this.internalRouteRequest,
    this.internalRouteMobilityType = 'SENIOR',
    this.routeDraftController,
    this.mapLauncher = const UrlLauncherKakaoMapLauncher(),
    this.onClose,
    this.previousStation,
    this.nextStation,
    this.onSelectNeighbor,
    this.lineForChrome,
    super.key,
  });

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final FavoriteStationRepository? favoriteRepository;
  final AdRepository? adRepository;
  final RealtimeRepository? realtimeRepository;
  final CurrentLocationProvider? locationProvider;
  final String stationId;
  final bool? initiallyFavorite;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository? internalRouteRepository;
  final InternalRouteRequest? internalRouteRequest;
  final String internalRouteMobilityType;
  final RouteDraftController? routeDraftController;
  final KakaoMapLauncher mapLauncher;
  final VoidCallback? onClose;
  final StationDetailNeighbor? previousStation;
  final StationDetailNeighbor? nextStation;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;
  final StationSearchLine? lineForChrome;

  @override
  State<StationDetailExpandHost> createState() =>
      _StationDetailExpandHostState();
}

class _StationDetailExpandHostState extends State<StationDetailExpandHost> {
  late final StationDetailController _controller;
  StationFavoriteToggleController? _favoriteController;
  InternalRouteController? _internalRouteController;

  @override
  void initState() {
    super.initState();
    _controller = StationDetailController(
      repository: widget.repository,
      realtimeRepository: widget.realtimeRepository,
    );
    _bindInternalRoute(widget.stationId);
    _bindFavorite(widget.stationId, widget.initiallyFavorite);
    _controller.load(widget.stationId);
  }

  @override
  void didUpdateWidget(covariant StationDetailExpandHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stationId != widget.stationId) {
      _bindInternalRoute(widget.stationId);
      _bindFavorite(widget.stationId, widget.initiallyFavorite);
      _controller.load(widget.stationId);
    }
  }

  void _bindInternalRoute(String stationId) {
    final repository = widget.internalRouteRepository;
    if (repository == null) {
      _internalRouteController?.dispose();
      _internalRouteController = null;
      return;
    }
    _internalRouteController ??= InternalRouteController(
      repository: repository,
    );
    final request = widget.internalRouteRequest;
    if (request != null) {
      _internalRouteController!.load(request);
    } else {
      _internalRouteController!.loadDefault(
        stationId: stationId,
        mobilityType: widget.internalRouteMobilityType,
      );
    }
  }

  void _bindFavorite(String stationId, bool? initiallyFavorite) {
    final repository = widget.favoriteRepository;
    _favoriteController?.dispose();
    _favoriteController = null;
    if (repository == null) {
      return;
    }
    _favoriteController = StationFavoriteToggleController(
      repository: repository,
      stationId: stationId,
      initiallyFavorite: initiallyFavorite ?? false,
      initiallyChecking: initiallyFavorite == null,
    );
    if (initiallyFavorite == null) {
      _favoriteController!.load();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _favoriteController?.dispose();
    _internalRouteController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, ?_internalRouteController]),
      builder: (context, _) {
        return ColoredBox(
          color: EasySubwayAccessibleColors.surface,
          child: StationDetailBody(
            state: _controller.state,
            onRetryRealtime: _controller.retryRealtime,
            internalRouteState: _internalRouteController?.state,
            reportRepository: widget.reportRepository,
            favoriteController: _favoriteController,
            adRepository: widget.adRepository,
            routeDraftController: widget.routeDraftController,
            locationProvider: widget.locationProvider,
            mapLauncher: widget.mapLauncher,
            facilityReportDraftTargetStore:
                widget.facilityReportDraftTargetStore,
            timetableRepository: widget.repository is StationTimetableRepository
                ? widget.repository as StationTimetableRepository
                : null,
            showContextChrome: true,
            onClose: widget.onClose,
            previousStation: widget.previousStation,
            nextStation: widget.nextStation,
            onSelectNeighbor: widget.onSelectNeighbor,
            lineForChrome: widget.lineForChrome,
          ),
        );
      },
    );
  }
}
