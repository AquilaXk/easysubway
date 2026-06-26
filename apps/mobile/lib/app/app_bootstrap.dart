import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../facility_report.dart';
import '../favorite_facility.dart';
import '../internal_route.dart';
import '../mobile_error_reporter.dart';
import '../notification_settings.dart';
import '../route_search.dart';
import '../station_search.dart';
import '../core/datapack/data_pack_client.dart';
import '../core/datapack/data_pack_installer.dart';
import '../core/datapack/data_pack_update_state.dart';
import '../core/datapack/data_pack_updater.dart';
import '../core/datapack/emergency_override_repository.dart';
import '../user_data_deletion.dart';
import '../core/database/catalog/catalog_database.dart';
import '../core/database/catalog/catalog_database_opener.dart';
import '../core/database/user/user_database.dart';
import '../core/database/user/user_database_opener.dart';
import 'app_endpoints.dart';
import 'app_dependencies.dart';

typedef DataPackUpdateRunner =
    Future<void> Function({
      required Directory supportDirectory,
      required UserDatabase userDatabase,
    });

class AppBootstrap {
  const AppBootstrap({
    required this.dependencies,
    required this.catalogDatabase,
    required this.userDatabase,
    required this.dataPackUpdate,
  });

  final AppDependencies dependencies;
  final CatalogDatabase catalogDatabase;
  final UserDatabase userDatabase;
  final Future<void> dataPackUpdate;

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
    SearchHistoryRepository? searchHistoryRepository,
    InternalRouteRepository? internalRouteRepository,
    NotificationSettingsRepository? notificationRepository,
    NotificationPermissionProvider? notificationPermissionProvider,
    CurrentLocationProvider? locationProvider,
    UserDataDeletionRepository? userDataDeletionRepository,
    DataPackUpdateRunner? dataPackUpdateRunner,
    required bool enablePushNotifications,
  }) async {
    final supportDirectory =
        databaseDirectory ?? await getApplicationSupportDirectory();
    final userDatabase = await UserDatabaseOpener(
      databaseDirectory: Directory(p.join(supportDirectory.path, 'user')),
    ).open();
    final emergencyOverrideRepository = EmergencyOverrideRepository(
      userDatabase: userDatabase,
    );

    final dataPackUpdate = _runDataPackUpdateSafely(
      supportDirectory: supportDirectory,
      userDatabase: userDatabase,
      runner: dataPackUpdateRunner ?? _defaultDataPackUpdateRunner,
    );

    try {
      final catalogDatabase = await CatalogDatabaseOpener(
        databaseDirectory: supportDirectory,
        assetBundle: assetBundle ?? rootBundle,
        emergencyOverrideRepository: emergencyOverrideRepository,
      ).open();

      final dependencies = AppDependencies.resolve(
        repository: repository,
        reportRepository: reportRepository,
        routeRepository: routeRepository,
        routeFeedbackRepository: routeFeedbackRepository,
        favoriteRepository: favoriteRepository,
        favoriteFacilityRepository: favoriteFacilityRepository,
        favoriteRouteRepository: favoriteRouteRepository,
        searchHistoryRepository: searchHistoryRepository,
        internalRouteRepository: internalRouteRepository,
        notificationRepository: notificationRepository,
        notificationPermissionProvider: notificationPermissionProvider,
        locationProvider: locationProvider,
        userDataDeletionRepository: userDataDeletionRepository,
        catalogDatabase: catalogDatabase,
        userDatabase: userDatabase,
        enablePushNotifications: enablePushNotifications,
      );

      return AppBootstrap(
        dependencies: dependencies,
        catalogDatabase: catalogDatabase,
        userDatabase: userDatabase,
        dataPackUpdate: dataPackUpdate,
      );
    } catch (error, stackTrace) {
      await dataPackUpdate;
      await userDatabase.close();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> close() async {
    await dataPackUpdate;
    await catalogDatabase.close();
    await userDatabase.close();
  }
}

Future<void> _runDataPackUpdateSafely({
  required Directory supportDirectory,
  required UserDatabase userDatabase,
  required DataPackUpdateRunner runner,
}) async {
  try {
    await runner(
      supportDirectory: supportDirectory,
      userDatabase: userDatabase,
    );
  } catch (error, stackTrace) {
    reportMobileError(error, stackTrace, context: '데이터팩 업데이트 확인 중 예외가 발생했습니다.');
  }
}

Future<void> _defaultDataPackUpdateRunner({
  required Directory supportDirectory,
  required UserDatabase userDatabase,
}) async {
  final endpoints = AppEndpoints.fromEnvironment();
  final manifestUri = endpoints.dataPackManifestUri;
  if (manifestUri == null) {
    return;
  }
  final stateRepository = DataPackUpdateStateRepository(
    userDatabase: userDatabase,
  );
  final catalogDirectory = Directory(p.join(supportDirectory.path, 'catalog'));
  await DataPackUpdater(
    client: DataPackClient(
      manifestUri: manifestUri,
      stateRepository: stateRepository,
      productionSigningPublicKey: endpoints.productionDataPackSigningPublicKey,
      expectedManifestChannel: endpoints.expectedDataPackChannel,
    ),
    installer: DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    ),
    emergencyOverrideRepository: EmergencyOverrideRepository(
      userDatabase: userDatabase,
    ),
  ).checkForUpdates();
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
