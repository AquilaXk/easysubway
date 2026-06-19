import '../anonymous_auth.dart';
import '../auth_headers.dart';
import '../facility_report.dart';
import '../favorite_facility.dart';
import '../internal_route.dart';
import '../notification_settings.dart';
import '../route_search.dart';
import '../station_search.dart';
import '../user_data_deletion.dart';
import '../core/database/catalog/catalog_database.dart';
import '../features/internal_route/data/local_internal_route_repository.dart';
import '../features/routes/data/local_route_repository.dart';

class AppDependencies {
  const AppDependencies({
    required this.repository,
    required this.reportRepository,
    required this.routeRepository,
    required this.routeFeedbackRepository,
    required this.favoriteRepository,
    required this.favoriteFacilityRepository,
    required this.favoriteRouteRepository,
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
    InternalRouteRepository? internalRouteRepository,
    NotificationSettingsRepository? notificationRepository,
    NotificationPermissionProvider? notificationPermissionProvider,
    CurrentLocationProvider? locationProvider,
    AnonymousAuthRepository? anonymousAuthRepository,
    AnonymousAuthCredentialStore? anonymousAuthCredentialStore,
    UserDataDeletionRepository? userDataDeletionRepository,
    CatalogDatabase? catalogDatabase,
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
              _defaultNotificationSettingsRepository(
                baseUri: baseUri,
                authProvider: sharedAuthProvider,
              )
        : null;
    final resolvedNotificationPermissionProvider = pushNotificationsEnabled
        ? notificationPermissionProvider
        : null;

    return AppDependencies(
      repository: repository ?? StationSearchApiRepository(baseUri: baseUri),
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
              : LocalRouteRepository(catalogDatabase: catalogDatabase)),
      routeFeedbackRepository:
          routeFeedbackRepository ??
          _defaultRouteFeedbackRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      favoriteRepository:
          favoriteRepository ??
          _defaultFavoriteStationRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      favoriteFacilityRepository:
          favoriteFacilityRepository ??
          _defaultFavoriteFacilityRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      favoriteRouteRepository:
          favoriteRouteRepository ??
          _defaultFavoriteRouteRepository(
            baseUri: baseUri,
            authProvider: sharedAuthProvider,
          ),
      internalRouteRepository:
          internalRouteRepository ??
          (catalogDatabase == null
              ? InternalRouteApiRepository(baseUri: baseUri)
              : LocalInternalRouteRepository(catalogDatabase: catalogDatabase)),
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
