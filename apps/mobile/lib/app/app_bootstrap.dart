import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../anonymous_auth.dart';
import '../facility_report.dart';
import '../favorite_facility.dart';
import '../internal_route.dart';
import '../notification_settings.dart';
import '../route_search.dart';
import '../station_search.dart';
import '../user_data_deletion.dart';
import '../core/database/catalog/catalog_database.dart';
import '../core/database/catalog/catalog_database_opener.dart';
import '../core/database/user/user_database.dart';
import '../core/database/user/user_database_opener.dart';
import 'app_dependencies.dart';

class AppBootstrap {
  const AppBootstrap({
    required this.dependencies,
    required this.catalogDatabase,
    required this.userDatabase,
  });

  final AppDependencies dependencies;
  final CatalogDatabase catalogDatabase;
  final UserDatabase userDatabase;

  static Future<AppBootstrap> initialize({
    Directory? databaseDirectory,
    AssetBundle? assetBundle,
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
    required bool enableAnonymousAuth,
    required bool enablePushNotifications,
  }) async {
    final supportDirectory =
        databaseDirectory ?? await getApplicationSupportDirectory();
    final catalogDatabase = await CatalogDatabaseOpener(
      databaseDirectory: supportDirectory,
      assetBundle: assetBundle ?? rootBundle,
    ).open();
    final userDatabase = await UserDatabaseOpener(
      databaseDirectory: Directory(p.join(supportDirectory.path, 'user')),
    ).open();

    final dependencies = AppDependencies.resolve(
      repository: repository,
      reportRepository: reportRepository,
      routeRepository: routeRepository,
      routeFeedbackRepository: routeFeedbackRepository,
      favoriteRepository: favoriteRepository,
      favoriteFacilityRepository: favoriteFacilityRepository,
      favoriteRouteRepository: favoriteRouteRepository,
      internalRouteRepository: internalRouteRepository,
      notificationRepository: notificationRepository,
      notificationPermissionProvider: notificationPermissionProvider,
      locationProvider: locationProvider,
      anonymousAuthRepository: anonymousAuthRepository,
      anonymousAuthCredentialStore: anonymousAuthCredentialStore,
      userDataDeletionRepository: userDataDeletionRepository,
      catalogDatabase: catalogDatabase,
      enableAnonymousAuth: enableAnonymousAuth,
      enablePushNotifications: enablePushNotifications,
    );

    return AppBootstrap(
      dependencies: dependencies,
      catalogDatabase: catalogDatabase,
      userDatabase: userDatabase,
    );
  }

  Future<void> close() async {
    await catalogDatabase.close();
    await userDatabase.close();
  }
}

class AppBootstrapLifecycle extends StatefulWidget {
  const AppBootstrapLifecycle({
    required this.close,
    required this.child,
    super.key,
  });

  final Future<void> Function() close;
  final Widget child;

  @override
  State<AppBootstrapLifecycle> createState() => _AppBootstrapLifecycleState();
}

class _AppBootstrapLifecycleState extends State<AppBootstrapLifecycle> {
  @override
  void dispose() {
    unawaited(widget.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
