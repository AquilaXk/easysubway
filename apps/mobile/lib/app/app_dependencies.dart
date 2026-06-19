import '../anonymous_auth.dart';
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
    required this.anonymousAuthSession,
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
    AnonymousAuthRepository? anonymousAuthRepository,
    AnonymousAuthCredentialStore? anonymousAuthCredentialStore,
    UserDataDeletionRepository? userDataDeletionRepository,
    CatalogDatabase? catalogDatabase,
    UserDatabase? userDatabase,
    required bool enableAnonymousAuth,
    required bool enablePushNotifications,
  }) {
    final baseUri = defaultStationApiBaseUri();
    final anonymousAuthSession = _defaultAnonymousAuthSession(
      baseUri: baseUri,
      anonymousAuthRepository: anonymousAuthRepository,
      credentialStore: anonymousAuthCredentialStore,
      enableAnonymousAuth: enableAnonymousAuth,
    );
    final sharedAuthProvider = anonymousAuthSession;
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
                      authProvider: sharedAuthProvider,
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
            authProvider: sharedAuthProvider,
          ),
      routeRepository:
          routeRepository ??
          (catalogDatabase == null
              ? RouteSearchApiRepository(baseUri: baseUri)
              : FallbackRouteSearchRepository(
                  localRepository: LocalRouteRepository(
                    catalogDatabase: catalogDatabase,
                  ),
                  apiRepository: RouteSearchApiRepository(baseUri: baseUri),
                )),
      routeFeedbackRepository:
          routeFeedbackRepository ??
          _defaultRouteFeedbackRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      favoriteRepository:
          favoriteRepository ??
          (catalogDatabase != null && userDatabase != null
              ? DriftFavoriteStationRepository(
                  catalogDatabase: catalogDatabase,
                  userDatabase: userDatabase,
                )
              : _defaultFavoriteStationRepository(
                  baseUri: baseUri,
                  authProvider: sharedAuthProvider,
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
                  authProvider: sharedAuthProvider,
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
                  authProvider: sharedAuthProvider,
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
                  apiRepository: InternalRouteApiRepository(baseUri: baseUri),
                )),
      notificationRepository: resolvedNotificationRepository,
      notificationPermissionProvider: resolvedNotificationPermissionProvider,
      locationProvider:
          locationProvider ?? MethodChannelCurrentLocationProvider(),
      userDataDeletionRepository:
          userDataDeletionRepository ??
          _defaultUserDataDeletionRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      anonymousAuthSession: anonymousAuthSession,
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
  final AnonymousAuthSession? anonymousAuthSession;
}

AnonymousAuthSession? _defaultAnonymousAuthSession({
  required Uri baseUri,
  required bool enableAnonymousAuth,
  AnonymousAuthRepository? anonymousAuthRepository,
  AnonymousAuthCredentialStore? credentialStore,
}) {
  if (!enableAnonymousAuth) {
    return null;
  }
  return AnonymousAuthSession(
    repository:
        anonymousAuthRepository ?? AnonymousAuthApiRepository(baseUri: baseUri),
    credentialStore: credentialStore,
  );
}

UserDataDeletionRepository? _defaultUserDataDeletionRepository({
  required Uri baseUri,
  required AuthorizationHeaderProvider? authProvider,
}) {
  if (authProvider == null) {
    return null;
  }
  return UserDataDeletionApiRepository(
    baseUri: baseUri,
    authProvider: authProvider,
    refreshExistingAuthorization: authProvider is AnonymousAuthSession
        ? authProvider.refreshExistingAuthorization
        : null,
  );
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
