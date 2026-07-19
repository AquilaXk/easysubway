import '../auth_headers.dart';
import '../core/database/catalog/catalog_database.dart';
import '../core/database/user/user_database.dart';
import '../core/network/api_client.dart';
import '../facility_report.dart';
import '../favorite_facility.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../features/favorites/data/drift_favorite_repositories.dart';
import '../features/fare/official_od_fare_repository.dart';
import '../features/ads/ad_repository.dart';
import '../features/get_off_alarm/data/get_off_alarm_recovery_notice_store.dart';
import '../features/get_off_alarm/data/get_off_alarm_state_repository.dart';
import '../features/get_off_alarm/exact_alarm_permission.dart';
import '../features/get_off_alarm/get_off_alarm_controller.dart';
import '../features/get_off_alarm/get_off_alarm_notifier.dart';
import '../features/get_off_alarm/get_off_alarm_reconcile_worker.dart';
import '../features/network_map/data/drift_network_map_viewport_repository.dart';
import '../features/preferences/data/drift_notification_settings_repository.dart';
import '../features/realtime/realtime_repository.dart';
import '../features/search_history/data/drift_search_history_repository.dart';
import '../features/service_notice/data/drift_notice_cache_store.dart';
import '../features/service_notice/data/notice_repository.dart';
import '../features/stations/data/drift_station_repository.dart';
import '../features/stations/data/current_location_provider.dart';
import '../features/stations/data/station_api_repository.dart';
import '../features/stations/domain/station_repositories.dart';
import '../features/train_search/data/train_search_repository.dart';
import '../features/train_search/domain/train_search_models.dart';
import '../features/train_search/domain/train_search_scope_policy.dart';
import '../internal_route.dart';
import '../network_map.dart';
import '../notification_settings.dart';
import '../route_search.dart';
import '../route_v2_ingress.dart';
import '../station_search.dart' show defaultOptionalStationApiBaseUri;
import '../user_data_deletion.dart';
import '../features/internal_route/data/local_internal_route_repository.dart';
import '../features/routes/data/local_route_repository.dart'
    show
        LocalFirstRouteSearchRepository,
        LocalRouteRepository,
        OnlineFirstRouteSearchRepository,
        RouteSearchOnlineFirstMetrics;

class AppDependencies {
  const AppDependencies({
    required this.repository,
    required this.reportRepository,
    required this.routeRepository,
    required this.routeFeedbackRepository,
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
    required this.searchHistoryRepository,
    required this.internalRouteRepository,
    required this.networkMapRepository,
    required this.networkMapViewportRepository,
    required this.realtimeRepository,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.locationProvider,
    required this.trainSearchRepository,
    required this.userDataDeletionRepository,
    this.getOffAlarmController,
    required this.noticeRepository,
    this.adRepository,
  });

  factory AppDependencies.resolve({
    StationSearchRepository? repository,
    FacilityReportRepository? reportRepository,
    RouteSearchRepository? routeRepository,
    LocalRouteRepository? localRouteRepository,
    RouteFeedbackRepository? routeFeedbackRepository,
    FavoriteStationRepository? favoriteRepository,
    FavoriteFacilityRepository? favoriteFacilityRepository,
    FavoriteRouteRepository? favoriteRouteRepository,
    SearchHistoryRepository? searchHistoryRepository,
    InternalRouteRepository? internalRouteRepository,
    NetworkMapRepository? networkMapRepository,
    NetworkMapViewportRepository? networkMapViewportRepository,
    RealtimeRepository? realtimeRepository,
    NotificationSettingsRepository? notificationRepository,
    NotificationPermissionProvider? notificationPermissionProvider,
    CurrentLocationProvider? locationProvider,
    TrainSearchRepository? trainSearchRepository,
    UserDataDeletionRepository? userDataDeletionRepository,
    NoticeRepository? noticeRepository,
    AdRepository? adRepository,
    CatalogDatabase? catalogDatabase,
    UserDatabase? userDatabase,
    Uri? Function() apiBaseUri = defaultOptionalStationApiBaseUri,
    bool enableRouteV2OnlineFirst = const bool.fromEnvironment(
      'EASYSUBWAY_ROUTE_V2_ONLINE_FIRST_ENABLED',
      defaultValue: false,
    ),
    RouteSearchOnlineFirstMetrics? routeSearchOnlineFirstMetrics,
    PlayIntegrityAttestor? playIntegrityAttestor,
    required bool enablePushNotifications,
  }) {
    Uri? cachedBaseUri;
    var baseUriResolved = false;
    Uri? optionalBaseUri() {
      if (!baseUriResolved) {
        cachedBaseUri = apiBaseUri();
        baseUriResolved = true;
      }
      return cachedBaseUri;
    }

    Uri requireBaseUri() {
      final baseUri = optionalBaseUri();
      if (baseUri == null) {
        throw StateError('Release API base URL must be configured.');
      }
      return baseUri;
    }

    final pushNotificationsEnabled =
        enablePushNotifications ||
        notificationRepository != null ||
        notificationPermissionProvider != null;
    final resolvedNotificationRepository = pushNotificationsEnabled
        ? notificationRepository ??
              (userDatabase != null
                  ? DriftNotificationSettingsRepository(
                      userDatabase: userDatabase,
                    )
                  : _defaultNotificationSettingsRepository(
                      baseUri: requireBaseUri,
                      authProvider: null,
                    ))
        : null;
    final resolvedNotificationPermissionProvider = pushNotificationsEnabled
        ? notificationPermissionProvider
        : null;

    final StationSearchRepository resolvedStationRepository =
        repository ??
        (catalogDatabase != null
            ? DriftStationRepository(database: catalogDatabase)
            : StationSearchApiRepository(baseUri: requireBaseUri()));
    final injectedNetworkMapRepository = repository is NetworkMapRepository
        ? repository as NetworkMapRepository
        : null;
    final resolvedNetworkMapRepository =
        networkMapRepository ??
        injectedNetworkMapRepository ??
        (catalogDatabase != null
            ? DriftStationRepository(database: catalogDatabase)
            : const _UnavailableNetworkMapRepository());

    final resolvedRealtimeRepository =
        realtimeRepository ??
        _defaultRealtimeRepository(baseUri: optionalBaseUri);
    final resolvedLocalRouteRepository =
        localRouteRepository ??
        (catalogDatabase == null
            ? null
            : LocalRouteRepository(
                catalogDatabase: catalogDatabase,
                officialOdFareRepository: OfficialOdFareRepository(
                  catalogDatabase: catalogDatabase,
                ),
              ));

    return AppDependencies(
      repository: resolvedStationRepository,
      reportRepository:
          reportRepository ??
          _defaultFacilityReportRepository(
            baseUri: optionalBaseUri,
            userDatabase: userDatabase,
          ),
      routeRepository:
          routeRepository ??
          (() {
            if (!enableRouteV2OnlineFirst) {
              return resolvedLocalRouteRepository == null
                  ? RouteSearchApiRepository(baseUri: requireBaseUri())
                  : LocalFirstRouteSearchRepository(
                      localRepository: resolvedLocalRouteRepository,
                    );
            }
            if (resolvedLocalRouteRepository == null) {
              throw StateError(
                'Route V2 online-first requires a local catalog database.',
              );
            }
            final routeV2BaseUri = requireBaseUri();
            final local = LocalFirstRouteSearchRepository(
              localRepository: resolvedLocalRouteRepository,
            );
            final sessionProvider = PlayIntegrityRouteV2SessionProvider(
              apiClient: ApiClient(baseUri: routeV2BaseUri),
              attestor:
                  playIntegrityAttestor ?? MethodChannelPlayIntegrityAttestor(),
            );
            return TransportScopedRouteSearchRepository(
              localRepository: local,
              itxOnlineRepository: OnlineFirstRouteSearchRepository(
                onlineRepository: RouteSearchV2ApiRepository(
                  baseUri: routeV2BaseUri,
                  bearerTokenProvider: sessionProvider.issueToken,
                  bearerTokenInvalidator: sessionProvider.invalidateSession,
                ),
                localRepository: resolvedLocalRouteRepository,
                metrics: routeSearchOnlineFirstMetrics,
              ),
            );
          })(),
      routeFeedbackRepository:
          routeFeedbackRepository ??
          _defaultRouteFeedbackRepository(
            baseUri: requireBaseUri,
            authProvider: null,
          ),
      favoriteRepository:
          favoriteRepository ??
          (catalogDatabase != null && userDatabase != null
              ? DriftFavoriteStationRepository(
                  catalogDatabase: catalogDatabase,
                  userDatabase: userDatabase,
                )
              : _defaultFavoriteStationRepository(
                  baseUri: requireBaseUri,
                  authProvider: null,
                )),
      favoriteFacilityRepository:
          favoriteFacilityRepository ??
          (catalogDatabase != null && userDatabase != null
              ? DriftFavoriteFacilityRepository(
                  catalogDatabase: catalogDatabase,
                  userDatabase: userDatabase,
                )
              : _defaultFavoriteFacilityRepository(
                  baseUri: requireBaseUri,
                  authProvider: null,
                )),
      favoriteRouteRepository:
          favoriteRouteRepository ??
          (catalogDatabase != null && userDatabase != null
              ? DriftFavoriteRouteRepository(
                  catalogDatabase: catalogDatabase,
                  userDatabase: userDatabase,
                )
              : _defaultFavoriteRouteRepository(
                  baseUri: requireBaseUri,
                  authProvider: null,
                )),
      searchHistoryRepository:
          searchHistoryRepository ??
          (userDatabase == null
              ? null
              : DriftSearchHistoryRepository(userDatabase: userDatabase)),
      internalRouteRepository:
          internalRouteRepository ??
          (catalogDatabase == null
              ? InternalRouteApiRepository(baseUri: requireBaseUri())
              : LocalFirstInternalRouteRepository(
                  localRepository: LocalInternalRouteRepository(
                    catalogDatabase: catalogDatabase,
                  ),
                )),
      networkMapRepository: resolvedNetworkMapRepository,
      networkMapViewportRepository:
          networkMapViewportRepository ??
          (userDatabase == null
              ? null
              : DriftNetworkMapViewportRepository(userDatabase: userDatabase)),
      realtimeRepository: resolvedRealtimeRepository,
      notificationRepository: resolvedNotificationRepository,
      notificationPermissionProvider: resolvedNotificationPermissionProvider,
      locationProvider:
          locationProvider ?? MethodChannelCurrentLocationProvider(),
      trainSearchRepository:
          trainSearchRepository ??
          _LazyDefaultTrainSearchRepository(optionalBaseUri),
      userDataDeletionRepository:
          userDataDeletionRepository ??
          _defaultUserDataDeletionRepository(
            baseUri: requireBaseUri,
            authProvider: null,
            userDatabase: userDatabase,
          ),
      getOffAlarmController: _resolveGetOffAlarmController(
        userDatabase,
        resolvedNotificationPermissionProvider,
      ),
      noticeRepository:
          noticeRepository ??
          (userDatabase == null
              ? null
              : _LazyDefaultNoticeRepository(optionalBaseUri, userDatabase)),
      adRepository: adRepository ?? AdRepository.lazy(optionalBaseUri),
    );
  }

  final StationSearchRepository repository;
  final FacilityReportRepository reportRepository;
  final RouteSearchRepository routeRepository;
  final RouteFeedbackRepository? routeFeedbackRepository;
  final FavoriteStationRepository? favoriteRepository;
  final FavoriteFacilityRepository? favoriteFacilityRepository;
  final FavoriteRouteRepository? favoriteRouteRepository;
  final SearchHistoryRepository? searchHistoryRepository;
  final InternalRouteRepository internalRouteRepository;
  final NetworkMapRepository networkMapRepository;
  final NetworkMapViewportRepository? networkMapViewportRepository;
  final RealtimeRepository realtimeRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
  final TrainSearchRepository trainSearchRepository;
  final UserDataDeletionRepository? userDataDeletionRepository;
  final GetOffAlarmController? getOffAlarmController;
  final NoticeRepository? noticeRepository;
  final AdRepository? adRepository;
}

class _LazyDefaultTrainSearchRepository implements TrainSearchRepository {
  _LazyDefaultTrainSearchRepository(this._baseUri);

  final Uri? Function() _baseUri;
  TrainSearchRepository? _delegate;

  TrainSearchRepository _resolveDelegate() {
    final cachedDelegate = _delegate;
    if (cachedDelegate != null) return cachedDelegate;
    final resolvedBaseUri = _baseUri();
    return _delegate = resolvedBaseUri == null
        ? const UnavailableTrainSearchRepository()
        : ApiTrainSearchRepository(ApiClient(baseUri: resolvedBaseUri));
  }

  @override
  Future<TrainSearchResult> search(TrainSearchCriteria criteria) =>
      _resolveDelegate().search(criteria);

  @override
  Future<List<TrainStation>> stations(
    String query, {
    TrainSearchTrainType? type,
  }) => _resolveDelegate().stations(query, type: type);
}

/// 공개 공지 API는 선택 기능이라 앱 시작 중 base URL을 강제 평가하지 않는다.
/// 첫 조회 시점에 base URL을 해소하고, 없으면 조용히 빈 결과를 돌려준다.
class _LazyDefaultNoticeRepository implements NoticeRepository {
  _LazyDefaultNoticeRepository(this._baseUri, this._userDatabase);

  final Uri? Function() _baseUri;
  final UserDatabase _userDatabase;
  NoticeRepository? _delegate;

  @override
  Future<ActiveNoticesResult> activeNotices() {
    return _resolveDelegate().activeNotices();
  }

  NoticeRepository _resolveDelegate() {
    final cachedDelegate = _delegate;
    if (cachedDelegate != null) {
      return cachedDelegate;
    }
    final resolvedBaseUri = _baseUri();
    final resolvedDelegate = resolvedBaseUri == null
        ? const _UnavailableNoticeRepository()
        : ApiNoticeRepository(
            apiClient: HttpNoticeApiClient(ApiClient(baseUri: resolvedBaseUri)),
            cacheStore: DriftNoticeCacheStore(userDatabase: _userDatabase),
          );
    _delegate = resolvedDelegate;
    return resolvedDelegate;
  }
}

class _UnavailableNoticeRepository implements NoticeRepository {
  const _UnavailableNoticeRepository();

  @override
  Future<ActiveNoticesResult> activeNotices() async {
    return const ActiveNoticesResult(notices: [], stale: false);
  }
}

RealtimeRepository _defaultRealtimeRepository({
  required Uri? Function() baseUri,
}) {
  return _LazyDefaultRealtimeRepository(baseUri);
}

class _LazyDefaultRealtimeRepository implements RealtimeRepository {
  _LazyDefaultRealtimeRepository(this._baseUri);

  final Uri? Function() _baseUri;
  RealtimeRepository? _delegate;

  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) {
    return _resolveDelegate().arrivals(query);
  }

  RealtimeRepository _resolveDelegate() {
    final cachedDelegate = _delegate;
    if (cachedDelegate != null) {
      return cachedDelegate;
    }
    final resolvedBaseUri = _baseUri();
    final resolvedDelegate = resolvedBaseUri == null
        ? const UnavailableRealtimeRepository()
        : RealtimeApiRepository(baseUri: resolvedBaseUri);
    _delegate = resolvedDelegate;
    return resolvedDelegate;
  }
}

class _UnavailableNetworkMapRepository implements NetworkMapRepository {
  const _UnavailableNetworkMapRepository();

  @override
  Future<NetworkMapData> getNetworkMap({String? region, String? lineId}) async {
    final selectedRegion = region ?? '수도권';
    return NetworkMapData(
      regions: const [
        NetworkMapRegion(name: '수도권'),
        NetworkMapRegion(name: '부산'),
        NetworkMapRegion(name: '광주'),
        NetworkMapRegion(name: '대구'),
        NetworkMapRegion(name: '대전'),
      ],
      selectedRegion: selectedRegion,
      lines: const [],
      stations: const [],
      edges: const [],
      positionSources: const [],
    );
  }
}

GetOffAlarmController? _resolveGetOffAlarmController(
  UserDatabase? userDatabase,
  NotificationPermissionProvider? notificationPermissionProvider,
) {
  if (userDatabase == null) {
    return null;
  }
  final plugin = FlutterLocalNotificationsPlugin();
  return GetOffAlarmController(
    notifier: LocalGetOffAlarmNotifier(plugin),
    permissionGate: PluginExactAlarmPermissionGate(plugin),
    notificationPermissionProvider:
        notificationPermissionProvider ??
        MethodChannelNotificationPermissionProvider(),
    repository: DriftGetOffAlarmStateRepository(userDatabase: userDatabase),
    recoveryNoticeStore: DriftGetOffAlarmRecoveryNoticeStore(
      userDatabase: userDatabase,
    ),
    onActivateReconcileWork: registerGetOffAlarmReconcile,
    onDeactivateReconcileWork: cancelGetOffAlarmReconcile,
  );
}

FacilityReportRepository _defaultFacilityReportRepository({
  required Uri? Function() baseUri,
  required UserDatabase? userDatabase,
}) {
  return _LazyDefaultFacilityReportRepository(baseUri, userDatabase);
}

class _LazyDefaultFacilityReportRepository implements FacilityReportRepository {
  _LazyDefaultFacilityReportRepository(this._baseUri, this._userDatabase);

  // 시설 신고 API는 선택 기능이라 앱 시작 중 base URL을 강제 평가하지 않는다.
  final Uri? Function() _baseUri;
  final UserDatabase? _userDatabase;
  FacilityReportRepository? _delegate;

  @override
  Future<FacilityReportResult> createReport(FacilityReportRequest request) {
    return _resolveDelegate().createReport(request);
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) {
    return _resolveDelegate().getReport(reportId);
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() {
    return _resolveDelegate().listMyReports();
  }

  FacilityReportRepository _resolveDelegate() {
    final cachedDelegate = _delegate;
    if (cachedDelegate != null) {
      return cachedDelegate;
    }
    final resolvedDelegate = _createDelegate();
    _delegate = resolvedDelegate;
    return resolvedDelegate;
  }

  FacilityReportRepository _createDelegate() {
    final resolvedBaseUri = _baseUri();
    if (resolvedBaseUri == null) {
      return const UnavailableFacilityReportRepository();
    }
    return FacilityReportApiRepository(
      baseUri: resolvedBaseUri,
      apiClient: ApiClient(baseUri: resolvedBaseUri),
      authProvider: null,
      receiptStore: _userDatabase == null
          ? null
          : DriftFacilityReportReceiptStore(userDatabase: _userDatabase),
    );
  }
}

UserDataDeletionRepository? _defaultUserDataDeletionRepository({
  required Uri Function() baseUri,
  required AuthorizationHeaderProvider? authProvider,
  required UserDatabase? userDatabase,
}) {
  final localRepository = userDatabase == null
      ? null
      : UserDataDeletionLocalRepository(userDatabase: userDatabase);
  final remoteRepository = authProvider == null
      ? null
      : (() {
          final resolvedBaseUri = baseUri();
          return UserDataDeletionApiRepository(
            baseUri: resolvedBaseUri,
            apiClient: ApiClient(baseUri: resolvedBaseUri),
            authProvider: authProvider,
          );
        })();
  if (remoteRepository != null && localRepository != null) {
    return UserDataDeletionCompositeRepository(
      remoteRepository: remoteRepository,
      localRepository: localRepository,
    );
  }
  return remoteRepository ?? localRepository;
}

FavoriteStationRepository? _defaultFavoriteStationRepository({
  required Uri Function() baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return FavoriteStationApiRepository(
    baseUri: baseUri(),
    authProvider: authProvider,
  );
}

FavoriteFacilityRepository? _defaultFavoriteFacilityRepository({
  required Uri Function() baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return FavoriteFacilityApiRepository(
    baseUri: baseUri(),
    authProvider: authProvider,
  );
}

FavoriteRouteRepository? _defaultFavoriteRouteRepository({
  required Uri Function() baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return FavoriteRouteApiRepository(
    baseUri: baseUri(),
    authProvider: authProvider,
  );
}

RouteFeedbackRepository? _defaultRouteFeedbackRepository({
  required Uri Function() baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return RouteFeedbackApiRepository(
    baseUri: baseUri(),
    authProvider: authProvider,
  );
}

NotificationSettingsRepository? _defaultNotificationSettingsRepository({
  required Uri Function() baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return NotificationSettingsApiRepository(
    baseUri: baseUri(),
    authProvider: authProvider,
  );
}
