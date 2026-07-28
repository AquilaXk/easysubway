import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../adaptive_layout.dart';
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
import 'station_exit_section.dart';
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

/// 이전·다음 역 맥락(노선도 확장·시트 상단 chrome용).
class StationDetailNeighbor {
  const StationDetailNeighbor({required this.stationId, required this.nameKo});

  final String stationId;
  final String nameKo;

  String get displayName => nameKo.endsWith('역') ? nameKo : '$nameKo역';
}

/// 역 상세 공통 본문. 검색·즐겨찾기 시트와 노선도 확장(PR-B)이 공유한다.
///
/// IA(#2436): 맥락 → 지금 열차 → 이용하기 → 출구 → 시설 → 주소·연락처(있을 때)
/// → 안내·출처 → 광고. 카카오버스류 배너는 넣지 않는다.
class StationDetailBody extends StatelessWidget {
  const StationDetailBody({
    required this.state,
    required this.onRetryRealtime,
    required this.reportRepository,
    this.internalRouteState,
    this.favoriteController,
    this.adRepository,
    this.routeDraftController,
    this.locationProvider,
    this.mapLauncher = const UrlLauncherKakaoMapLauncher(),
    this.facilityReportDraftTargetStore,
    this.timetableRepository,
    this.showContextChrome = false,
    this.showRealtimeSection = true,
    this.onClose,
    this.previousStation,
    this.nextStation,
    this.onSelectNeighbor,
    this.lineForChrome,
    super.key,
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
  final bool showContextChrome;

  /// false면 「지금 열차」블록을 생략한다. 노선도 확장처럼 상단에
  /// 실시간/시간표 패널을 이미 붙인 셸에서 중복·실패 카드 교체를 막는다.
  final bool showRealtimeSection;
  final VoidCallback? onClose;
  final StationDetailNeighbor? previousStation;
  final StationDetailNeighbor? nextStation;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;
  final StationSearchLine? lineForChrome;

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
        showContextChrome: showContextChrome,
        showRealtimeSection: showRealtimeSection,
        onClose: onClose,
        previousStation: previousStation,
        nextStation: nextStation,
        onSelectNeighbor: onSelectNeighbor,
        lineForChrome: lineForChrome,
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
    required this.showContextChrome,
    required this.showRealtimeSection,
    required this.onClose,
    required this.previousStation,
    required this.nextStation,
    required this.onSelectNeighbor,
    required this.lineForChrome,
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
  final bool showContextChrome;
  final bool showRealtimeSection;
  final VoidCallback? onClose;
  final StationDetailNeighbor? previousStation;
  final StationDetailNeighbor? nextStation;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;
  final StationSearchLine? lineForChrome;

  @override
  Widget build(BuildContext context) {
    // 카카오식 IA(#2436): 지금 열차 → 이용하기 → 출구 → 시설 → 안내·출처 → 광고.
    final primaryChildren = <Widget>[
      if (showContextChrome) ...[
        _StationDetailContextChrome(
          detail: detail,
          line: lineForChrome ?? _primaryStationLine(detail),
          onClose: onClose,
          previousStation: previousStation,
          nextStation: nextStation,
          onSelectNeighbor: onSelectNeighbor,
        ),
        const SizedBox(height: 16),
      ],
      if (showRealtimeSection) ...[
        const _StationDetailSectionTitle(title: '지금 열차'),
        const SizedBox(height: 12),
        StationRealtimeSummary(
          snapshot: realtimeSnapshot,
          onRetry: onRetryRealtime,
        ),
        const SizedBox(height: 20),
      ],
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

    final hasExits = exits.isNotEmpty;
    final hasFacilities =
        facilities.isNotEmpty || facilityAttentionSummary.isNotEmpty;

    final detailChildren = <Widget>[
      if (hasExits) ...[
        const _StationDetailSectionTitle(title: '출구 정보'),
        const SizedBox(height: 8),
        StationExitSection(
          key: ValueKey('stationExitSection-${detail.id}'),
          station: detail,
          exits: exits,
          mapLauncher: mapLauncher,
          locationProvider: locationProvider,
        ),
        const SizedBox(height: 12),
      ],
      if (hasFacilities) ...[
        const _StationDetailSectionTitle(title: '시설 정보'),
        const SizedBox(height: 8),
        if (facilityAttentionSummary.isNotEmpty) ...[
          StationFacilityStatusSummary(
            text: facilityAttentionSummary,
            semanticLabel: facilityAttentionSemanticLabel,
          ),
          const SizedBox(height: 12),
        ],
        for (final facility in facilities)
          StationFacilityCard(
            facility: facility,
            station: detail,
            onReportTap: () => _openFacilityReport(context, facility),
          ),
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
        const _StationDetailSectionTitle(title: '역 안 이동'),
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

StationSearchLine? _primaryStationLine(StationDetail detail) {
  if (detail.lines.isEmpty) {
    return null;
  }
  return detail.lines.first;
}

class _StationDetailContextChrome extends StatelessWidget {
  const _StationDetailContextChrome({
    required this.detail,
    required this.line,
    required this.onClose,
    required this.previousStation,
    required this.nextStation,
    required this.onSelectNeighbor,
  });

  final StationDetail detail;
  final StationSearchLine? line;
  final VoidCallback? onClose;
  final StationDetailNeighbor? previousStation;
  final StationDetailNeighbor? nextStation;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;

  @override
  Widget build(BuildContext context) {
    final hasNeighbors = previousStation != null || nextStation != null;
    return Column(
      key: const Key('stationDetailContextChrome'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (line != null) ...[
              StationLineBadge(line: line!, size: 28),
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
            if (onClose != null)
              IconButton(
                key: const Key('stationDetailChromeCloseButton'),
                tooltip: '닫기',
                onPressed: onClose,
                style: IconButton.styleFrom(
                  minimumSize: const Size.square(EasySubwayTouchTarget.general),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(
                  Icons.close,
                  size: 26,
                  color: EasySubwayAccessibleColors.contentPrimary,
                ),
              ),
          ],
        ),
        if (hasNeighbors) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NeighborStationButton(
                  key: const Key('stationDetailPreviousStation'),
                  neighbor: previousStation,
                  alignment: Alignment.centerLeft,
                  onSelectNeighbor: onSelectNeighbor,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${detail.nameKo}역',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: EasySubwayAccessibleColors.text,
                    // #1915: 섹션/컨텍스트 헤더는 w800 금지. 화면 타이틀 전용 ratchet.
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
              Expanded(
                child: _NeighborStationButton(
                  key: const Key('stationDetailNextStation'),
                  neighbor: nextStation,
                  alignment: Alignment.centerRight,
                  onSelectNeighbor: onSelectNeighbor,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NeighborStationButton extends StatelessWidget {
  const _NeighborStationButton({
    required this.neighbor,
    required this.alignment,
    required this.onSelectNeighbor,
    super.key,
  });

  final StationDetailNeighbor? neighbor;
  final Alignment alignment;
  final ValueChanged<StationDetailNeighbor>? onSelectNeighbor;

  @override
  Widget build(BuildContext context) {
    final value = neighbor;
    if (value == null) {
      return const SizedBox.shrink();
    }
    final enabled = onSelectNeighbor != null;
    return Align(
      alignment: alignment,
      child: TextButton(
        onPressed: enabled ? () => onSelectNeighbor!(value) : null,
        style: TextButton.styleFrom(
          minimumSize: const Size(48, EasySubwayTouchTarget.general),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: EasySubwayAccessibleColors.secondaryText,
        ),
        child: Text(
          value.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignment == Alignment.centerRight
              ? TextAlign.right
              : TextAlign.left,
        ),
      ),
    );
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
