import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../adaptive_layout.dart';
import '../../../app/easy_subway_family_app_bar.dart';
import '../../../core/external/kakao_map_launcher.dart';
import '../../../facility_report.dart';
import '../../../internal_route.dart';
import '../../../mobile_error_reporter.dart';
import '../../ads/active_ad_banner.dart';
import '../../ads/ad_repository.dart';
import '../../realtime/realtime_repository.dart';
import '../../route_draft/application/route_draft_controller.dart';
import '../application/station_detail_controller.dart';
import '../domain/station_line.dart';
import '../domain/station_models.dart';
import '../domain/station_repositories.dart';
import 'station_detail_route_actions.dart';
import 'station_exit_card.dart';
import 'station_facility_card.dart';
import 'station_facility_status_summary.dart';
import 'station_info_basis_disclosure.dart';
import 'station_internal_route_guidance.dart';
import 'station_layout_summary.dart';
import 'station_line_badges.dart';
import 'station_realtime_summary.dart';
import 'station_timetable_screen.dart';

const _stationDetailPagePadding = EdgeInsets.fromLTRB(20, 12, 20, 32);
const _stationDetailLargePagePadding = EdgeInsets.fromLTRB(24, 16, 24, 40);

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
              child: _StationDetailBody(
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

    final primaryLine = _primaryStationLine(detail);

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

StationSearchLine? _primaryStationLine(StationDetail detail) {
  if (detail.lines.isEmpty) {
    return null;
  }
  return detail.lines.first;
}

class _StationDetailBody extends StatelessWidget {
  const _StationDetailBody({
    required this.state,
    required this.onRetryRealtime,
    required this.internalRouteState,
    required this.reportRepository,
    required this.favoriteController,
    required this.adRepository,
    required this.routeDraftController,
    required this.locationProvider,
    required this.mapLauncher,
    required this.facilityReportDraftTargetStore,
    required this.timetableRepository,
  });

  final StationDetailState state;
  final VoidCallback onRetryRealtime;
  final InternalRouteState? internalRouteState;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;
  final AdRepository? adRepository;
  final RouteDraftController? routeDraftController;
  final CurrentLocationProvider? locationProvider;
  final KakaoMapLauncher mapLauncher;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final StationTimetableRepository? timetableRepository;

  @override
  Widget build(BuildContext context) {
    return switch (state.status) {
      StationDetailStatus.loading => Semantics(
        label: '역 안내 불러오는 중',
        liveRegion: true,
        child: const Center(child: CircularProgressIndicator()),
      ),
      StationDetailStatus.failure => Padding(
        padding: const EdgeInsets.all(20),
        child: _StationDetailMessage(message: state.message, liveRegion: true),
      ),
      StationDetailStatus.success => _StationDetailContent(
        detail: state.detail!,
        exits: state.exits,
        facilities: state.prioritizedFacilities,
        facilityAttentionSummary: state.facilityAttentionSummary,
        facilityAttentionSemanticLabel: state.facilityAttentionSemanticLabel,
        layoutSummaryItems: state.layoutSummaryItems,
        layoutSummarySemanticLabel: state.layoutSummarySemanticLabel,
        realtimeSnapshot: state.realtimeSnapshot,
        onRetryRealtime: onRetryRealtime,
        internalRouteState: internalRouteState,
        reportRepository: reportRepository,
        favoriteController: favoriteController,
        adRepository: adRepository,
        routeDraftController: routeDraftController,
        locationProvider: locationProvider,
        mapLauncher: mapLauncher,
        facilityReportDraftTargetStore: facilityReportDraftTargetStore,
        timetableRepository: timetableRepository,
      ),
    };
  }
}

class _StationDetailMessage extends StatelessWidget {
  const _StationDetailMessage({required this.message, this.liveRegion = false});

  final String message;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: liveRegion,
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: EasySubwayAccessibleColors.secondaryText,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _StationDetailContent extends StatelessWidget {
  const _StationDetailContent({
    required this.detail,
    required this.exits,
    required this.facilities,
    required this.facilityAttentionSummary,
    required this.facilityAttentionSemanticLabel,
    required this.layoutSummaryItems,
    required this.layoutSummarySemanticLabel,
    required this.realtimeSnapshot,
    required this.onRetryRealtime,
    required this.internalRouteState,
    required this.reportRepository,
    required this.favoriteController,
    required this.adRepository,
    required this.routeDraftController,
    required this.locationProvider,
    required this.mapLauncher,
    required this.facilityReportDraftTargetStore,
    required this.timetableRepository,
  });

  final StationDetail detail;
  final List<StationExitInfo> exits;
  final List<StationFacilityInfo> facilities;
  final String facilityAttentionSummary;
  final String facilityAttentionSemanticLabel;
  final List<StationLayoutSummaryItem> layoutSummaryItems;
  final String layoutSummarySemanticLabel;
  final RealtimeSnapshot realtimeSnapshot;
  final VoidCallback onRetryRealtime;
  final InternalRouteState? internalRouteState;
  final FacilityReportRepository reportRepository;
  final StationFavoriteToggleController? favoriteController;
  final AdRepository? adRepository;
  final RouteDraftController? routeDraftController;
  final CurrentLocationProvider? locationProvider;
  final KakaoMapLauncher mapLauncher;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final StationTimetableRepository? timetableRepository;

  @override
  Widget build(BuildContext context) {
    // 패밀리룩(#2436): AppBar에 호선·역명. 본문은
    // 지금 열차 → 이용하기 → 역 정보 → 안내 순.
    final primaryChildren = <Widget>[
      const _StationDetailSectionTitle(title: '지금 열차'),
      const SizedBox(height: 12),
      StationRealtimeSummary(
        snapshot: realtimeSnapshot,
        onRetry: onRetryRealtime,
      ),
      const SizedBox(height: 20),
      const _StationDetailSectionTitle(title: '이용하기'),
      const SizedBox(height: 12),
      StationDetailRouteActions(
        detail: detail,
        routeDraftController: routeDraftController,
        favoriteController: favoriteController,
      ),
      const SizedBox(height: 12),
      _StationTimetableEntry(detail: detail, repository: timetableRepository),
    ];

    final internalRouteStateValue = internalRouteState;
    final hasInternalRouteGuidance =
        internalRouteStateValue != null &&
        internalRouteStateValue.status != InternalRouteViewStatus.unavailable;

    final hasStationInfo =
        facilityAttentionSummary.isNotEmpty ||
        exits.isNotEmpty ||
        facilities.isNotEmpty;

    final detailChildren = <Widget>[
      if (hasStationInfo) ...[
        const _StationDetailSectionTitle(title: '역 정보'),
        const SizedBox(height: 8),
        if (facilityAttentionSummary.isNotEmpty) ...[
          StationFacilityStatusSummary(
            text: facilityAttentionSummary,
            semanticLabel: facilityAttentionSemanticLabel,
          ),
          const SizedBox(height: 12),
        ],
        if (exits.isNotEmpty) ...[
          for (final exit in exits)
            StationExitCard(
              station: detail,
              exit: exit,
              mapLauncher: mapLauncher,
              locationProvider: locationProvider,
            ),
        ],
        if (facilities.isNotEmpty) ...[
          for (final facility in facilities)
            StationFacilityCard(
              facility: facility,
              station: detail,
              onReportTap: () => _openFacilityReport(context, facility),
            ),
        ],
        const SizedBox(height: 12),
      ],
      const _StationDetailSectionTitle(title: '안내'),
      const SizedBox(height: 12),
      if (detail.nameSub.isNotEmpty) ...[
        Text(
          detail.nameSub,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: EasySubwayAccessibleColors.secondaryText,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
      ],
      Text(
        '마지막 확인',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: EasySubwayAccessibleColors.mutedText,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        stationVerifiedRelativeLabel(detail.lastVerifiedAt),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: EasySubwayAccessibleColors.mutedText,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
      if (layoutSummaryItems.isNotEmpty || hasInternalRouteGuidance) ...[
        const SizedBox(height: 16),
        Text(
          '역 안 이동',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: EasySubwayAccessibleColors.text,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        if (layoutSummaryItems.isNotEmpty) ...[
          StationLayoutSummary(
            items: layoutSummaryItems,
            semanticLabel: layoutSummarySemanticLabel,
          ),
          if (hasInternalRouteGuidance) const SizedBox(height: 16),
        ],
        if (hasInternalRouteGuidance)
          StationInternalRouteGuidance(state: internalRouteState!),
      ],
      const SizedBox(height: 16),
      StationInfoBasisDisclosure(
        labels: [
          detail.dataSourceLabel,
          '마지막 확인 ${stationVerifiedRelativeLabel(detail.lastVerifiedAt)}',
        ],
      ),
      if (adRepository case final repository?) ...[
        const SizedBox(height: 24),
        ActiveAdBanner(
          key: const Key('stationDetailBottomAdBanner'),
          repository: repository,
          placement: AdPlacement.stationDetailBottom,
        ),
      ],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = EasySubwayAdaptiveLayout.isLargeScreen(
          constraints,
          textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
        );
        return ListView(
          key: const Key('stationDetailList'),
          padding: isLargeScreen
              ? _stationDetailLargePagePadding
              : _stationDetailPagePadding,
          children: isLargeScreen
              ? [
                  _StationDetailAdaptiveContent(
                    primaryChildren: primaryChildren,
                    detailChildren: detailChildren,
                  ),
                ]
              : [
                  ...primaryChildren,
                  const SizedBox(height: 24),
                  ...detailChildren,
                ],
        );
      },
    );
  }

  void _openFacilityReport(BuildContext context, StationFacilityInfo facility) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FacilityReportScreen(
          repository: reportRepository,
          locationLoader: _locationLoader(),
          needsLocationPermissionRequest: _locationPermissionRequestChecker(),
          openLocationSettings: _locationSettingsOpener(),
          draftTargetStore: facilityReportDraftTargetStore,
          target: FacilityReportTarget(
            stationId: detail.id,
            stationName: detail.nameKo,
            facilityId: facility.id,
            facilityName: facility.name,
            facilityTypeLabel: facility.typeLabel,
            facilityStatusLabel: facility.statusLabel,
          ),
        ),
      ),
    );
  }

  FacilityReportLocationLoader? _locationLoader() {
    final provider = locationProvider;
    if (provider == null) {
      return null;
    }
    return () async {
      final CurrentLocation location;
      try {
        location = await provider.currentLocation();
      } on CurrentLocationException catch (error) {
        throw FacilityReportLocationException(error.message);
      }
      return FacilityReportLocation(
        latitude: location.latitude,
        longitude: location.longitude,
      );
    };
  }

  FacilityReportLocationPermissionRequestChecker?
  _locationPermissionRequestChecker() {
    final provider = locationProvider;
    if (provider == null) {
      return null;
    }
    return provider.needsLocationPermissionRequest;
  }

  FacilityReportLocationSettingsOpener? _locationSettingsOpener() {
    final provider = locationProvider;
    if (provider == null) {
      return null;
    }
    return provider.openLocationSettings;
  }
}

class _StationTimetableEntry extends StatefulWidget {
  const _StationTimetableEntry({required this.detail, this.repository});

  final StationDetail detail;
  final StationTimetableRepository? repository;

  @override
  State<_StationTimetableEntry> createState() => _StationTimetableEntryState();
}

class _StationTimetableEntryState extends State<_StationTimetableEntry> {
  StationTimetable? _timetable;

  @override
  void initState() {
    super.initState();
    final repository = widget.repository;
    if (repository != null && widget.detail.lines.isNotEmpty) {
      unawaited(_load(repository, widget.detail.lines));
    }
  }

  Future<void> _load(
    StationTimetableRepository repository,
    List<StationSearchLine> lines,
  ) async {
    try {
      final timetable = await loadFirstAvailableStationTimetable(
        stationId: widget.detail.id,
        lines: lines,
        repository: repository,
        date: debugStationVerifiedClock(),
      );
      if (mounted && timetable != null) {
        setState(() => _timetable = timetable);
      }
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 상세 시간표 요약 조회 중 예외가 발생했습니다.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final timetable = _timetable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 로컬 coverage가 없으면 준비 중 문구 대신 요약 줄을 그리지 않는다(#2078).
        // '시간표 보기' 버튼은 남겨 전체 시간표 화면으로 진입할 수 있게 한다.
        if (timetable != null && timetable.isAvailable) ...[
          for (final direction in timetable.directions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${direction.name} · 첫차 ${direction.firstDeparture.timeLabel} · '
                '막차 ${direction.lastDeparture.timeLabel}',
              ),
            ),
          const SizedBox(height: 4),
        ],
        TextButton.icon(
          key: const Key('stationTimetableButton'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => StationTimetableScreen(
                stationId: widget.detail.id,
                stationName: widget.detail.nameKo,
                lines: widget.detail.lines,
                repository: widget.repository,
              ),
            ),
          ),
          icon: const Icon(Icons.schedule),
          label: const Text('시간표 보기'),
        ),
      ],
    );
  }
}

class _StationDetailAdaptiveContent extends StatelessWidget {
  const _StationDetailAdaptiveContent({
    required this.primaryChildren,
    required this.detailChildren,
  });

  final List<Widget> primaryChildren;
  final List<Widget> detailChildren;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: EasySubwayAdaptiveLayout.largeScreenMaxContentWidth,
        ),
        child: Row(
          key: const Key('stationDetailLargeScreenLayout'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Column(
                key: const Key('stationDetailPrimaryColumn'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: primaryChildren,
              ),
            ),
            const SizedBox(
              width: EasySubwayAdaptiveLayout.largeScreenColumnGap,
            ),
            Expanded(
              flex: 5,
              child: Column(
                key: const Key('stationDetailDetailColumn'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: detailChildren,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StationDetailSectionTitle extends StatelessWidget {
  const _StationDetailSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: EasySubwayAccessibleColors.scaffoldSurface,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.secondaryText,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
