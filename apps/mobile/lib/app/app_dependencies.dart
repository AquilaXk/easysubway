import '../auth_headers.dart';
import '../core/database/catalog/catalog_database.dart';
import '../core/database/user/user_database.dart';
import '../facility_report.dart';
import '../favorite_facility.dart';
import '../features/favorites/data/drift_favorite_repositories.dart';
import '../features/preferences/data/drift_notification_settings_repository.dart';
import '../features/search_history/data/drift_search_history_repository.dart';
import '../features/stations/data/drift_station_repository.dart';
import '../internal_route.dart';
import '../notification_settings.dart';
import '../route_search.dart';
import '../station_search.dart';
import '../user_data_deletion.dart';
import '../features/internal_route/data/local_internal_route_repository.dart';
import '../features/routes/data/local_route_repository.dart'
    show FallbackRouteSearchRepository, LocalRouteRepository;

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
    NotificationSettingsRepository? notificationRepository,
    NotificationPermissionProvider? notificationPermissionProvider,
    CurrentLocationProvider? locationProvider,
    UserDataDeletionRepository? userDataDeletionRepository,
    CatalogDatabase? catalogDatabase,
    UserDatabase? userDatabase,
    required bool enablePushNotifications,
  }) {
    final baseUri = defaultStationApiBaseUri();
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
                      baseUri: baseUri,
                      authProvider: null,
                    ))
        : null;
    final resolvedNotificationPermissionProvider = pushNotificationsEnabled
        ? notificationPermissionProvider
        : null;

    return AppDependencies(
      repository:
          repository ??
          (catalogDatabase != null
              ? DriftStationRepository(database: catalogDatabase)
              : StationSearchApiRepository(baseUri: baseUri)),
      reportRepository:
          reportRepository ??
          FacilityReportApiRepository(
            baseUri: baseUri,
            authProvider: null,
            receiptStore: userDatabase == null
                ? null
                : DriftFacilityReportReceiptStore(userDatabase: userDatabase),
          ),
      routeRepository:
          routeRepository ??
          (catalogDatabase == null
              ? RouteSearchApiRepository(baseUri: baseUri)
              : FallbackRouteSearchRepository(
                  localRepository: LocalRouteRepository(
                    catalogDatabase: catalogDatabase,
                  ),
                )),
      routeFeedbackRepository:
          routeFeedbackRepository ??
          _defaultRouteFeedbackRepository(baseUri: baseUri, authProvider: null),
      favoriteRepository:
          favoriteRepository ??
          (catalogDatabase != null && userDatabase != null
              ? DriftFavoriteStationRepository(
                  catalogDatabase: catalogDatabase,
                  userDatabase: userDatabase,
                )
              : _defaultFavoriteStationRepository(
                  baseUri: baseUri,
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
                  baseUri: baseUri,
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
                  baseUri: baseUri,
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
              ? InternalRouteApiRepository(baseUri: baseUri)
              : FallbackInternalRouteRepository(
                  localRepository: LocalInternalRouteRepository(
                    catalogDatabase: catalogDatabase,
                  ),
                )),
      notificationRepository: resolvedNotificationRepository,
      notificationPermissionProvider: resolvedNotificationPermissionProvider,
      locationProvider:
          locationProvider ?? MethodChannelCurrentLocationProvider(),
      userDataDeletionRepository:
          userDataDeletionRepository ??
          _defaultUserDataDeletionRepository(
            baseUri: baseUri,
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
  final NotificationSettingsRepository? notificationRepository;
  final NotificationPermissionProvider? notificationPermissionProvider;
  final CurrentLocationProvider locationProvider;
  final UserDataDeletionRepository? userDataDeletionRepository;
}

UserDataDeletionRepository? _defaultUserDataDeletionRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
  required UserDatabase? userDatabase,
}) {
  final localRepository = userDatabase == null
      ? null
      : UserDataDeletionLocalRepository(userDatabase: userDatabase);
  final remoteRepository = authProvider == null
      ? null
      : UserDataDeletionApiRepository(
          baseUri: baseUri,
          authProvider: authProvider,
        );
  if (remoteRepository != null && localRepository != null) {
    return UserDataDeletionCompositeRepository(
      remoteRepository: remoteRepository,
      localRepository: localRepository,
    );
  }
  return remoteRepository ?? localRepository;
}

FavoriteStationRepository? _defaultFavoriteStationRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return FavoriteStationApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
  );
}

FavoriteFacilityRepository? _defaultFavoriteFacilityRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return FavoriteFacilityApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
  );
}

FavoriteRouteRepository? _defaultFavoriteRouteRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return FavoriteRouteApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
  );
}

RouteFeedbackRepository? _defaultRouteFeedbackRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return RouteFeedbackApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
  );
}

NotificationSettingsRepository? _defaultNotificationSettingsRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return NotificationSettingsApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
  );
}
