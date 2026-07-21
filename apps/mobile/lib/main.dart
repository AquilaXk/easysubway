import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app_bootstrap.dart';
import 'app/demo_dependencies.dart';
import 'app/easy_subway_app.dart';
import 'core/datapack/data_pack_update_state.dart';
import 'features/get_off_alarm/get_off_alarm_controller.dart';
import 'features/home_widget/home_widget_link_handler.dart';
import 'features/home_widget/next_train_widget_repository.dart';
import 'features/home_widget/next_train_widget_runtime.dart'
    as next_train_widget_runtime;
import 'features/stations/presentation/station_detail_screen.dart';
import 'facility_report.dart';
import 'legacy_credential_cleanup.dart';
import 'mobile_error_reporter.dart';
import 'onboarding.dart';

const defaultPushNotificationsEnabled = bool.fromEnvironment(
  'EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS',
  defaultValue: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledAssetLicenses();
  validateReleaseBuildFlags(
    isReleaseMode: kReleaseMode,
    demoHomeDataEnabled: defaultDemoHomeDataEnabled,
  );
  final bootstrap = await AppBootstrap.initialize(
    enablePushNotifications: defaultPushNotificationsEnabled,
    favoriteRepository: defaultDemoHomeDataEnabled
        ? const DemoFavoriteStationRepository()
        : null,
    favoriteFacilityRepository: defaultDemoHomeDataEnabled
        ? const DemoFavoriteFacilityRepository()
        : null,
    favoriteRouteRepository: defaultDemoHomeDataEnabled
        ? const DemoFavoriteRouteRepository()
        : null,
    searchHistoryRepository: defaultDemoHomeDataEnabled
        ? DemoSearchHistoryRepository()
        : null,
  );
  // process-wide WorkManager dispatcher를 app bootstrap에서 정확히 1회 초기화한다.
  // 이후 하차 알림 복원과 위젯 startup은 각자 등록만 수행한다(재초기화 금지).
  await next_train_widget_runtime.initializeWorkManagerDispatcher();
  await restoreGetOffAlarmState(bootstrap.dependencies.getOffAlarmController);
  final nextTrainWidgetRepository = NextTrainWidgetRepository(
    catalogDatabase: bootstrap.catalogDatabase,
    userDatabase: bootstrap.userDatabase,
  );
  await next_train_widget_runtime.runNextTrainWidgetStartup(
    installedWidgetIds: next_train_widget_runtime.installedNextTrainWidgetIds,
    registerRefresh: next_train_widget_runtime.registerNextTrainWidgetRefresh,
    cancelRefresh: next_train_widget_runtime.cancelNextTrainWidgetRefresh,
    refresh: (widgetIds) => next_train_widget_runtime.refreshNextTrainWidgets(
      nextTrainWidgetRepository,
      widgetIds: widgetIds,
    ),
    reportError: (error, stackTrace) =>
        reportMobileError(error, stackTrace, context: '홈 위젯 초기화 중 예외가 발생했습니다.'),
  );
  final photoPicker = ImagePickerFacilityReportPhotoPicker();
  final navigatorKey = GlobalKey<NavigatorState>();
  final onboardingStore = const SecureOnboardingResultStore();
  final draftTargetStore = const SecureFacilityReportDraftTargetStore();
  runApp(
    AppBootstrapLifecycle(
      close: bootstrap.close,
      resumeDataPackUpdate: () async {
        await bootstrap.resumeDataPackUpdate();
        await next_train_widget_runtime.runNextTrainWidgetOperationSafely(
          operation: () => next_train_widget_runtime.refreshNextTrainWidgets(
            nextTrainWidgetRepository,
          ),
          reportError: (error, stackTrace) => reportMobileError(
            error,
            stackTrace,
            context: '홈 위젯 갱신 중 예외가 발생했습니다.',
          ),
        );
      },
      resumeGetOffAlarmState: () => reconcileGetOffAlarmState(
        bootstrap.dependencies.getOffAlarmController,
      ),
      child: HomeWidgetLinkHandler(
        clicks: next_train_widget_runtime.homeWidgetClicks(),
        navigatorKey: navigatorKey,
        stationDetailBuilder: (stationId) => StationDetailScreen(
          repository: bootstrap.dependencies.repository,
          reportRepository: bootstrap.dependencies.reportRepository,
          favoriteRepository: bootstrap.dependencies.favoriteRepository,
          adRepository: bootstrap.dependencies.adRepository,
          realtimeRepository: bootstrap.dependencies.realtimeRepository,
          locationProvider: bootstrap.dependencies.locationProvider,
          stationId: stationId,
          facilityReportDraftTargetStore: draftTargetStore,
          internalRouteRepository:
              bootstrap.dependencies.internalRouteRepository,
        ),
        child: EasySubwayApp(
          navigatorKey: navigatorKey,
          dependencies: bootstrap.dependencies,
          onboardingStore: onboardingStore,
          facilityReportDraftTargetStore: draftTargetStore,
          facilityReportLostPhotoRestorer: photoPicker.retrieveLostPhoto,
          legacyCredentialCleaner: const SecureLegacyCredentialCleaner(),
          dataPackUpdateStateRepository: DataPackUpdateStateRepository(
            userDatabase: bootstrap.userDatabase,
          ),
          onDataPackMeteredConsent: bootstrap.acceptMeteredDataPackUpdate,
          dataPackUpdate: bootstrap.dataPackUpdate,
          bundledDataPackFreshness: bootstrap.bundledDataPackFreshness,
        ),
      ),
    ),
  );
}

@visibleForTesting
void registerBundledAssetLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['empty-notices-illustration'],
      '''
Empty notices illustration from Customer Relation Vectors With Faces
Author: Anton Kalashnyk
Source: https://www.svgrepo.com/collection/customer-relation-vectors-with-faces/
License: CC Attribution
License URL: https://www.svgrepo.com/page/licensing/#CC%20Attribution
Changes: converted from SVG to PNG and colorized for EasySubway.
''',
    );
    yield const LicenseEntryWithLineBreaks(
      ['empty-recent-search-warning-illustration'],
      '''
Empty recent-search warning illustration
Source: https://www.svgrepo.com/svg/501793/warning
License: SVG Repo (see SVG Repo licensing)
License URL: https://www.svgrepo.com/page/licensing/
Changes: converted from SVG to PNG and colorized for EasySubway.
''',
    );
  });
}

@pragma('vm:entry-point')
Future<void> configureMain() => next_train_widget_runtime.configureMain();

@visibleForTesting
Future<void> restoreGetOffAlarmState(GetOffAlarmController? controller) async {
  try {
    await controller?.restore();
  } catch (error, stackTrace) {
    reportMobileError(
      error,
      stackTrace,
      context: '하차 알림 시작 상태 복원 중 예외가 발생했습니다.',
    );
  }
}

@visibleForTesting
Future<void> reconcileGetOffAlarmState(
  GetOffAlarmController? controller,
) async {
  try {
    await controller?.reconcile();
  } catch (error, stackTrace) {
    reportMobileError(
      error,
      stackTrace,
      context: '하차 알림 foreground 상태 재조정 중 예외가 발생했습니다.',
    );
  }
}

void validateReleaseBuildFlags({
  required bool isReleaseMode,
  required bool demoHomeDataEnabled,
}) {
  if (isReleaseMode && demoHomeDataEnabled) {
    throw StateError('EASYSUBWAY_DEMO_HOME_DATA is not allowed in release.');
  }
}
