import '../auth_headers.dart';
import '../core/database/catalog/catalog_database.dart';
import '../core/database/user/user_database.dart';
import '../core/network/api_client.dart';
import '../facility_report.dart';
import '../favorite_facility.dart';
import '../features/favorites/data/drift_favorite_repositories.dart';
import '../features/preferences/data/drift_notification_settings_repository.dart';
import '../features/realtime/realtime_repository.dart';
import '../features/search_history/data/drift_search_history_repository.dart';
import '../features/stations/data/station_api_repository.dart';
import '../features/stations/data/drift_station_repository.dart';
import '../internal_route.dart';
import '../network_map.dart';
import '../notification_settings.dart';
import '../route_search.dart';
import '../station_search.dart';
import '../user_data_deletion.dart';
import '../features/internal_route/data/local_internal_route_repository.dart';
import '../features/routes/data/local_route_repository.dart'
    show LocalFirstRouteSearchRepository, LocalRouteRepository;

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
    required this.realtimeRepository,
    required this.notificationRepository,
    required this.notificationPermissionProvider,
    required this.locationProvider,
    required this.userDataDeletionRepository,
  });

  factory AppDependencies.resolve({
    StationSearchRepository? repository,
    FacilityReportRepository? reportRepository,
    RouteSearchRepository? routeRepository,
    RouteFeedbackRepository? routeFeedbackRepository,
    FavoriteStationRepository? favoriteRepository,
    FavoriteFacilityRepository? favoriteFacilityRepository,
    FavoriteRouteRepository? favoriteRouteRepository,
    SearchHistoryRepository? searchHistoryRepository,
    InternalRouteRepository? internalRouteRepository,
    NetworkMapRepository? networkMapRepository,
    RealtimeRepository? realtimeRepository,
    NotificationSettingsRepository? notificationRepository,
    NotificationPermissionProvider? notificationPermissionProvider,
    CurrentLocationProvider? locationProvider,
    UserDataDeletionRepository? userDataDeletionRepository,
    CatalogDatabase? catalogDatabase,
    UserDatabase? userDatabase,
    Uri? Function() apiBaseUri = defaultOptionalStationApiBaseUri,
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
          (catalogDatabase == null
              ? RouteSearchApiRepository(baseUri: requireBaseUri())
              : LocalFirstRouteSearchRepository(
                  localRepository: LocalRouteRepository(
                    catalogDatabase: catalogDatabase,
                  ),
                )),
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
      realtimeRepository: resolvedRealtimeRepository,
      notificationRepository: resolvedNotificationRepository,
      notificationPermissionProvider: resolvedNotificationPermissionProvider,
      locationProvider:
          locationProvider ?? MethodChannelCurrentLocationProvider(),
      userDataDeletionRepository:
          userDataDeletionRepository ??
          _defaultUserDataDeletionRepository(
            baseUri: requireBaseUri,
            authProvider: null,
            userDatabase: userDatabase,
          ),
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
  final RealtimeRepository realtimeRepository;
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
  final UserDataDeletionRepository? userDataDeletionRepository;
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
