import 'dart:async';

import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../app/app_components.dart';
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

class _HomeSavedRouteCard extends StatelessWidget {
  const _HomeSavedRouteCard({
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
    final tappable = Semantics(
      button: true,
      label:
          '즐겨찾기 경로, $originName에서 $destinationName까지, ${route.lineLabel}, ${route.mobilityLabel}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              const Icon(
                Icons.route_outlined,
                color: EasySubwayAccessibleColors.primary,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$originName → $destinationName',
                      style: const TextStyle(
                        color: EasySubwayAccessibleColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _HomeMiniBadge(route.lineLabel),
                        _HomeMiniBadge(route.mobilityLabel),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return AppCard(
      showBorder: true,
      child: Row(
        children: [
          Expanded(child: tappable),
          const SizedBox(width: 8),
          if (onRemove != null)
            IconButton(
              key: Key('favoriteRouteRemoveButton-${route.favoriteRouteId}'),
              onPressed: onRemove,
              icon: const Icon(
                Icons.delete_outline,
                color: EasySubwayAccessibleColors.mutedText,
              ),
              tooltip: '즐겨찾기 경로 삭제',
            )
          else
            const Icon(
              Icons.chevron_right,
              color: EasySubwayAccessibleColors.brand,
            ),
        ],
      ),
    );
  }
}

String _stationNameWithSuffix(String name) {
  return name.endsWith('역') ? name : '$name역';
}

class _HomeMiniBadge extends StatelessWidget {
  const _HomeMiniBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: EasySubwayAccessibleColors.surface,
      side: const BorderSide(color: EasySubwayAccessibleColors.line),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      labelStyle: const TextStyle(
        color: EasySubwayAccessibleColors.secondaryText,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
    );
  }
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
      appBar: AppBar(title: const Text('즐겨찾기')),
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
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: mainListPagePadding,
                children: [
                  if (snapshot.connectionState != ConnectionState.done)
                    const LinearProgressIndicator(minHeight: 3),
                  if (hasError)
                    HomeStateCard(
                      key: const Key('favoriteHomeErrorState'),
                      icon: Icons.error_outline,
                      title: '즐겨찾기를 불러오지 못했어요',
                      subtitle: '잠시 후 다시 불러와 주세요.',
                      actionLabel: '다시 시도',
                      onAction: () {
                        setState(() {
                          _dataFuture = _loadData();
                        });
                      },
                    )
                  else if (data.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: AppCard(
                        child: AppInfoRow(
                          icon: Icons.bookmark_border,
                          iconColor: EasySubwayAccessibleColors.mutedText,
                          title: '즐겨찾기한 항목이 없습니다',
                          subtitle: '역, 시설, 경로에서 즐겨찾기를 추가해 주세요.',
                        ),
                      ),
                    )
                  else ...[
                    // 카테고리 카드·개수 없이 저장한 항목을 바로 나열한다. 섹션
                    // 헤더는 해당 항목이 있을 때만 보여준다(#1569).
                    if (data.stations.isNotEmpty) ...[
                      const AppSectionTitle(title: '역'),
                      for (final station in data.stations)
                        _FavoriteHomeStationRow(
                          station: station,
                          onTap: widget.favoriteRepository == null
                              ? null
                              : () => _openStationDetailFromFavorite(station),
                        ),
                    ],
                    if (data.routes.isNotEmpty) ...[
                      const AppSectionTitle(title: '경로'),
                      for (final route in data.routes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _HomeSavedRouteCard(
                            route: route,
                            onTap: () => _openRouteSearchFromFavorite(route),
                            onRemove: widget.favoriteRouteRepository == null
                                ? null
                                : () => _removeFavoriteRoute(route),
                          ),
                        ),
                    ],
                    if (data.facilities.isNotEmpty) ...[
                      const AppSectionTitle(title: '시설'),
                      for (final facility in data.facilities)
                        _FavoriteHomeFacilityRow(
                          facility: facility,
                          onReportTap: () =>
                              _openFacilityReportFromFavorite(facility),
                        ),
                    ],
                  ],
                ],
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

class _FavoriteHomeStationRow extends StatelessWidget {
  const _FavoriteHomeStationRow({required this.station, required this.onTap});

  final FavoriteStation station;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final name = _stationNameWithSuffix(station.nameKo);
    final lineLabel = station.lineLabel;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: lineLabel.isEmpty ? '즐겨찾기 역, $name' : '즐겨찾기 역, $name, $lineLabel',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          key: Key('favoriteHomeStationRow-${station.stationId}'),
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: EasySubwayAccessibleColors.line),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.train_outlined,
                  color: EasySubwayAccessibleColors.primary,
                  size: 26,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: EasySubwayAccessibleColors.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      if (lineLabel.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        _HomeMiniBadge(lineLabel),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: EasySubwayAccessibleColors.brand,
                ),
              ],
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
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: EasySubwayAccessibleColors.line),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Row(
        children: [
          const Icon(
            Icons.elevator_outlined,
            color: EasySubwayAccessibleColors.primary,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  facility.name,
                  style: const TextStyle(
                    color: EasySubwayAccessibleColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  facility.stationLabel,
                  style: const TextStyle(
                    color: EasySubwayAccessibleColors.mutedText,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
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
              child: const Text('시설 알려주기'),
            ),
        ],
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
