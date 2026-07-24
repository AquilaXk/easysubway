import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';
import '../../../facility_report.dart';
import '../../../favorite_facility.dart';
import '../../../internal_route.dart';
import '../../../mobile_error_reporter.dart';
import '../../../route_search.dart';
import '../../../station_search.dart';
import '../../ads/ad_repository.dart';
import '../../realtime/realtime_repository.dart';
import '../../route_draft/application/route_draft_controller.dart';
import '../../route_draft/domain/route_draft.dart';
import '../../stations/presentation/station_detail_screen.dart';

String _stationNameWithSuffix(String name) {
  return name.endsWith('역') ? name : '$name역';
}

class FavoriteHomeScreen extends StatefulWidget {
  const FavoriteHomeScreen({
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
    this.adRepository,
    required this.stationRepository,
    required this.reportRepository,
    required this.locationProvider,
    required this.facilityReportDraftTargetStore,
    required this.internalRouteRepository,
    required this.realtimeRepository,
    required this.routeDraftController,
    required this.initialMobilityType,
    this.onOpenRouteSearch,
    this.onShellBack,
    this.bottomNavigationBar,
    super.key,
  });

  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final AdRepository? adRepository;
  final StationSearchRepository stationRepository;
  final FacilityReportRepository reportRepository;
  final CurrentLocationProvider locationProvider;
  final FacilityReportDraftTargetStore? facilityReportDraftTargetStore;
  final InternalRouteRepository internalRouteRepository;
  final RealtimeRepository realtimeRepository;
  final RouteDraftController routeDraftController;
  final String initialMobilityType;
  final Future<void> Function([
    String? mobilityType,
    RouteTransportScope? transportScope,
  ])?
  onOpenRouteSearch;

  /// 루트 탭으로 열린 즐겨찾기에서 Navigator.pop이 안 될 때 이전 탭(없으면 홈)으로 돌아간다.
  final VoidCallback? onShellBack;
  final Widget? bottomNavigationBar;

  @override
  State<FavoriteHomeScreen> createState() => _FavoriteHomeScreenState();
}

class _FavoriteHomeScreenState extends State<FavoriteHomeScreen> {
  late Future<_FavoriteHomeData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('favoriteHomeScreen'),
      backgroundColor: EasySubwayAccessibleColors.surface,
      appBar: AppBar(
        key: const Key('favoriteHomeAppBar'),
        title: const Text('즐겨찾기'),
        toolbarHeight: 60,
        backgroundColor: EasySubwayAccessibleColors.topBarSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const Key('favoriteHomeBackButton'),
          tooltip: '뒤로',
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
              return;
            }
            widget.onShellBack?.call();
          },
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
        ),
        flexibleSpace: const Align(
          alignment: Alignment.bottomCenter,
          child: EasySubwayHeaderDivider(key: Key('favoriteHomeHeaderDivider')),
        ),
      ),
      bottomNavigationBar: widget.bottomNavigationBar,
      body: SafeArea(
        child: FutureBuilder<_FavoriteHomeData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            final data = snapshot.data ?? const _FavoriteHomeData();
            final hasError = snapshot.hasError;
            return RefreshIndicator(
              onRefresh: () async {
                final next = _loadData();
                setState(() {
                  _dataFuture = next;
                });
                try {
                  await next;
                } catch (error, stackTrace) {
                  reportMobileError(
                    error,
                    stackTrace,
                    context: '즐겨찾기 새로고침 중 예외가 발생했습니다.',
                  );
                }
              },
              // 빈/오류 상태는 내 제보처럼 본문 전체 높이를 기준으로 Align 한다.
              // (ListView 자식에 짧은 SizedBox만 주면 같은 -0.55라도 더 위로 붙는다.)
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewportHeight = constraints.maxHeight;
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      if (snapshot.connectionState != ConnectionState.done)
                        const LinearProgressIndicator(minHeight: 3),
                      if (hasError)
                        SizedBox(
                          height: viewportHeight,
                          child: _FavoriteHomeErrorState(
                            onRetry: () {
                              setState(() {
                                _dataFuture = _loadData();
                              });
                            },
                          ),
                        )
                      else if (snapshot.connectionState ==
                              ConnectionState.done &&
                          data.isEmpty)
                        SizedBox(
                          height: viewportHeight,
                          child: const _FavoriteHomeEmptyState(),
                        )
                      else ...[
                        // 카테고리 카드·개수 없이 저장한 항목을 바로 나열한다.
                        // ListView 자식은 헤더/행 단위로 펼쳐 IndexedSemantics가
                        // 행 라벨을 섹션 헤더에 합치지 않게 한다(#1569·#2436).
                        if (data.stations.isNotEmpty) ...[
                          const _FavoriteHomeSectionHeader(title: '역'),
                          for (
                            var index = 0;
                            index < data.stations.length;
                            index++
                          ) ...[
                            _FavoriteHomeStationRow(
                              station: data.stations[index],
                              onTap: widget.favoriteRepository == null
                                  ? null
                                  : () => _openStationDetailFromFavorite(
                                      data.stations[index],
                                    ),
                            ),
                            if (index < data.stations.length - 1)
                              const _FavoriteHomeRowDivider(),
                          ],
                        ],
                        if (data.routes.isNotEmpty) ...[
                          const _FavoriteHomeSectionHeader(title: '경로'),
                          for (
                            var index = 0;
                            index < data.routes.length;
                            index++
                          ) ...[
                            _FavoriteHomeRouteRow(
                              route: data.routes[index],
                              onTap: () => _openRouteSearchFromFavorite(
                                data.routes[index],
                              ),
                              onRemove: widget.favoriteRouteRepository == null
                                  ? null
                                  : () => _removeFavoriteRoute(
                                      data.routes[index],
                                    ),
                            ),
                            if (index < data.routes.length - 1)
                              const _FavoriteHomeRowDivider(),
                          ],
                        ],
                        if (data.facilities.isNotEmpty) ...[
                          const _FavoriteHomeSectionHeader(title: '시설'),
                          for (
                            var index = 0;
                            index < data.facilities.length;
                            index++
                          ) ...[
                            _FavoriteHomeFacilityRow(
                              facility: data.facilities[index],
                              onReportTap: () =>
                                  _openFacilityReportFromFavorite(
                                    data.facilities[index],
                                  ),
                            ),
                            if (index < data.facilities.length - 1)
                              const _FavoriteHomeRowDivider(),
                          ],
                        ],
                      ],
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<_FavoriteHomeData> _loadData() async {
    final stations =
        await widget.favoriteRepository?.listFavoriteStations() ??
        const <FavoriteStation>[];
    final facilities =
        await widget.favoriteFacilityRepository?.listFavoriteFacilities() ??
        const <FavoriteFacility>[];
    final routes =
        await widget.favoriteRouteRepository?.listFavoriteRoutes() ??
        const <FavoriteRoute>[];
    return _FavoriteHomeData(
      stations: stations,
      facilities: facilities,
      routes: routes,
    );
  }

  void _openRouteSearchFromFavorite(FavoriteRoute favorite) {
    widget.routeDraftController.clear();
    widget.routeDraftController.setOrigin(
      RouteDraftStation(
        id: favorite.originStationId,
        nameKo: favorite.originStationName,
      ),
    );
    widget.routeDraftController.setDestination(
      RouteDraftStation(
        id: favorite.destinationStationId,
        nameKo: favorite.destinationStationName,
      ),
    );
    final openRouteSearch = widget.onOpenRouteSearch;
    if (openRouteSearch == null) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
    unawaited(openRouteSearch(favorite.mobilityType, favorite.transportScope));
  }

  Future<void> _removeFavoriteRoute(FavoriteRoute favorite) async {
    final repository = widget.favoriteRouteRepository;
    if (repository == null) {
      return;
    }
    try {
      await repository.removeFavoriteRoute(favorite.favoriteRouteId);
    } catch (error, stackTrace) {
      reportMobileError(error, stackTrace, context: '즐겨찾기 경로 삭제 중 예외가 발생했습니다.');
    }
    await _reloadFavoritesAfterReturn();
  }

  Future<void> _openStationDetailFromFavorite(FavoriteStation favorite) async {
    final repository = widget.favoriteRepository;
    if (repository == null) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StationDetailScreen(
          repository: widget.stationRepository,
          reportRepository: widget.reportRepository,
          favoriteRepository: repository,
          adRepository: widget.adRepository,
          locationProvider: widget.locationProvider,
          realtimeRepository: widget.realtimeRepository,
          stationId: favorite.stationId,
          facilityReportDraftTargetStore: widget.facilityReportDraftTargetStore,
          internalRouteRepository: widget.internalRouteRepository,
          internalRouteMobilityType: widget.initialMobilityType,
          routeDraftController: widget.routeDraftController,
          // 즐겨찾기에서 들어온 역은 이미 저장 상태로 열어 바로 해제할 수 있게 한다.
          initiallyFavorite: true,
        ),
      ),
    );
    await _reloadFavoritesAfterReturn();
  }

  Future<void> _openFacilityReportFromFavorite(
    FavoriteFacility favorite,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FacilityReportScreen(
          repository: widget.reportRepository,
          locationLoader: _facilityReportLocationLoader(
            widget.locationProvider,
          ),
          needsLocationPermissionRequest:
              widget.locationProvider.needsLocationPermissionRequest,
          openLocationSettings: widget.locationProvider.openLocationSettings,
          draftTargetStore: widget.facilityReportDraftTargetStore,
          target: FacilityReportTarget(
            stationId: favorite.stationId,
            stationName: favorite.stationNameKo,
            facilityId: favorite.facilityId,
            facilityName: favorite.name,
            facilityTypeLabel: favorite.typeLabel,
            facilityStatusLabel: favorite.statusLabel,
          ),
        ),
      ),
    );
    await _reloadFavoritesAfterReturn();
  }

  Future<void> _reloadFavoritesAfterReturn() async {
    if (!mounted) {
      return;
    }
    final next = _loadData();
    setState(() {
      _dataFuture = next;
    });
    try {
      await next;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '즐겨찾기 화면 복귀 후 새로고침 중 예외가 발생했습니다.',
      );
    }
  }
}

class _FavoriteHomeData {
  const _FavoriteHomeData({
    this.stations = const [],
    this.facilities = const [],
    this.routes = const [],
  });

  final List<FavoriteStation> stations;
  final List<FavoriteFacility> facilities;
  final List<FavoriteRoute> routes;

  bool get isEmpty => stations.isEmpty && facilities.isEmpty && routes.isEmpty;
}

class _FavoriteHomeSectionHeader extends StatelessWidget {
  const _FavoriteHomeSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ColoredBox(
      key: Key('favoriteHomeSectionHeader-$title'),
      color: EasySubwayAccessibleColors.scaffoldSurface,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: textTheme.bodyMedium?.copyWith(
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

class _FavoriteHomeRowDivider extends StatelessWidget {
  const _FavoriteHomeRowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 20,
      endIndent: 20,
      color: EasySubwayAccessibleColors.line,
    );
  }
}

class _FavoriteHomeEmptyState extends StatelessWidget {
  const _FavoriteHomeEmptyState();

  // 역 검색 최근 검색 빈 상태와 동일 토큰(아이콘 56·글자 16·disclosure·정렬 -0.55).
  static const _iconSize = 56.0;
  static const _emptyTone = EasySubwayAccessibleColors.disclosure;

  @override
  Widget build(BuildContext context) {
    // 높이는 호출부가 viewport로 채운다. 내 제보처럼 Align만 둔다.
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_outline, size: _iconSize, color: _emptyTone),
            const SizedBox(height: EasySubwaySpacing.md),
            Text(
              '즐겨찾기한 항목이 없습니다.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: _emptyTone,
                fontWeight: FontWeight.w600,
                height: 1.35,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FavoriteHomeErrorState extends StatelessWidget {
  const _FavoriteHomeErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Align(
      key: const Key('favoriteHomeErrorState'),
      alignment: const Alignment(0, -0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '즐겨찾기를 불러오지 못했어요',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: EasySubwayAccessibleColors.text,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '잠시 후 다시 불러와 주세요.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: EasySubwayAccessibleColors.mutedText,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('favoriteHomeRetryButton'),
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

class _FavoriteHomeStationRow extends StatelessWidget {
  const _FavoriteHomeStationRow({required this.station, required this.onTap});

  final FavoriteStation station;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = _stationNameWithSuffix(station.nameKo);
    final lineLabel = station.lineLabel;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: lineLabel.isEmpty ? '즐겨찾기 역, $name' : '즐겨찾기 역, $name, $lineLabel',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          key: Key('favoriteHomeStationRow-${station.stationId}'),
          onTap: onTap,
          child: ColoredBox(
            color: EasySubwayAccessibleColors.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: textTheme.bodyLarge?.copyWith(
                            color: EasySubwayAccessibleColors.text,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        if (lineLabel.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            lineLabel,
                            style: textTheme.bodyMedium?.copyWith(
                              color: EasySubwayAccessibleColors.mutedText,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
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

class _FavoriteHomeRouteRow extends StatelessWidget {
  const _FavoriteHomeRouteRow({
    required this.route,
    required this.onTap,
    this.onRemove,
  });

  final FavoriteRoute route;
  final VoidCallback onTap;
  // 즐겨찾기 목록에서 바로 삭제할 수 있게 오른쪽 액션을 준다. null이면 진입 화살표만.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final originName = _stationNameWithSuffix(route.originStationName);
    final destinationName = _stationNameWithSuffix(
      route.destinationStationName,
    );
    final subtitle = [
      if (route.lineLabel.trim().isNotEmpty) route.lineLabel.trim(),
      if (route.mobilityLabel.trim().isNotEmpty) route.mobilityLabel.trim(),
    ].join(' · ');
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label:
          '즐겨찾기 경로, $originName에서 $destinationName까지, ${route.lineLabel}, ${route.mobilityLabel}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: ColoredBox(
            color: EasySubwayAccessibleColors.surface,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$originName → $destinationName',
                          style: textTheme.bodyLarge?.copyWith(
                            color: EasySubwayAccessibleColors.text,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: textTheme.bodyMedium?.copyWith(
                              color: EasySubwayAccessibleColors.mutedText,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onRemove == null)
                    const Icon(
                      Icons.chevron_right,
                      color: EasySubwayAccessibleColors.disclosure,
                    )
                  else
                    IconButton(
                      key: Key(
                        'favoriteRouteRemoveButton-${route.favoriteRouteId}',
                      ),
                      onPressed: onRemove,
                      tooltip: '즐겨찾기 경로 삭제',
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(
                          EasySubwayTouchTarget.general,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                      ),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: EasySubwayAccessibleColors.mutedText,
                      ),
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

class _FavoriteHomeFacilityRow extends StatelessWidget {
  const _FavoriteHomeFacilityRow({
    required this.facility,
    required this.onReportTap,
  });

  final FavoriteFacility facility;
  final VoidCallback? onReportTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: EasySubwayAccessibleColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    facility.name,
                    style: textTheme.bodyLarge?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    facility.stationLabel,
                    style: textTheme.bodyMedium?.copyWith(
                      color: EasySubwayAccessibleColors.mutedText,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            if (onReportTap != null)
              TextButton(
                key: Key('favoriteFacilityReportButton-${facility.facilityId}'),
                onPressed: onReportTap,
                child: const Text('시설 제보'),
              ),
          ],
        ),
      ),
    );
  }
}

FacilityReportLocationLoader _facilityReportLocationLoader(
  CurrentLocationProvider provider,
) {
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
