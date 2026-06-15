import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'auth_headers.dart';
import 'mobile_error_reporter.dart';

const _notificationSettingsTimeout = Duration(seconds: 8);
const _notificationSettingsLoadErrorMessage = '알림 설정을 불러오지 못했습니다.';
const _notificationSettingsSaveErrorMessage = '알림 설정을 저장하지 못했습니다.';
const _deviceRegistrationErrorMessage = '기기 알림 등록을 마치지 못했습니다.';

abstract class NotificationSettingsRepository {
  Future<NotificationSettings> getNotificationSettings();

  Future<NotificationSettings> saveNotificationSettings(
    NotificationSettings settings,
  );
}

abstract class DeviceRegistrationRepository {
  Future<RegisteredDevice> registerDevice(DeviceRegistrationRequest request);
}

class NotificationSettingsApiRepository
    implements NotificationSettingsRepository {
  NotificationSettingsApiRepository({
    required this.baseUri,
    required this.authProvider,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final HttpClient _httpClient;

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    final data = await _requestData(
      'GET',
      baseUri.resolve('/api/v1/me/notification-settings'),
      errorMessage: _notificationSettingsLoadErrorMessage,
    );
    if (data is! Map<String, Object?>) {
      throw const NotificationSettingsException(
        _notificationSettingsLoadErrorMessage,
      );
    }

    try {
      return NotificationSettings.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '알림 설정 조회 응답 처리 중 예외가 발생했습니다.',
      );
      throw const NotificationSettingsException(
        _notificationSettingsLoadErrorMessage,
      );
    }
  }

  @override
  Future<NotificationSettings> saveNotificationSettings(
    NotificationSettings settings,
  ) async {
    final data = await _requestData(
      'PUT',
      baseUri.resolve('/api/v1/me/notification-settings'),
      errorMessage: _notificationSettingsSaveErrorMessage,
      body: settings.toRequestJson(),
    );
    if (data is! Map<String, Object?>) {
      throw const NotificationSettingsException(
        _notificationSettingsSaveErrorMessage,
      );
    }

    try {
      return NotificationSettings.fromJson(data);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '알림 설정 저장 응답 처리 중 예외가 발생했습니다.',
      );
      throw const NotificationSettingsException(
        _notificationSettingsSaveErrorMessage,
      );
    }
  }

  Future<Object?> _requestData(
    String method,
    Uri uri, {
    required String errorMessage,
    Map<String, Object?>? body,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final request = await _httpClient
            .openUrl(method, uri)
            .timeout(_notificationSettingsTimeout);
        final authorizationHeader = await authProvider
            .authorizationHeader()
            .timeout(_notificationSettingsTimeout);
        if (authorizationHeader != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            authorizationHeader,
          );
        }
        if (body != null) {
          request.headers.contentType = ContentType.json;
          request.write(jsonEncode(body));
        }

        final response = await request.close().timeout(
          _notificationSettingsTimeout,
        );
        final responseBody = await utf8
            .decodeStream(response)
            .timeout(_notificationSettingsTimeout);

        if (response.statusCode == HttpStatus.unauthorized &&
            authorizationHeader != null &&
            attempt == 0) {
          // 익명 인증이 만료된 경우 저장소를 비우고 새 인증으로 한 번만 다시 시도한다.
          await authProvider.invalidateAuthorization().timeout(
            _notificationSettingsTimeout,
          );
          continue;
        }

        if (response.statusCode < HttpStatus.ok ||
            response.statusCode >= HttpStatus.multipleChoices) {
          throw NotificationSettingsException(errorMessage);
        }

        final decoded = jsonDecode(responseBody);
        if (decoded is! Map<String, Object?> || decoded['success'] != true) {
          throw NotificationSettingsException(errorMessage);
        }
        return decoded['data'];
      } on NotificationSettingsException {
        rethrow;
      } catch (error, stackTrace) {
        reportMobileError(
          error,
          stackTrace,
          context: '알림 설정 API 요청 처리 중 예외가 발생했습니다.',
        );
        throw NotificationSettingsException(errorMessage);
      }
    }
    throw NotificationSettingsException(errorMessage);
  }
}

class DeviceRegistrationApiRepository implements DeviceRegistrationRepository {
  DeviceRegistrationApiRepository({
    required this.baseUri,
    required this.authProvider,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final AuthorizationHeaderProvider authProvider;
  final HttpClient _httpClient;

  @override
  Future<RegisteredDevice> registerDevice(
    DeviceRegistrationRequest registrationRequest,
  ) async {
    try {
      return await _postDeviceWithAuthorizationRetry(registrationRequest);
    } on NotificationSettingsException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '기기 알림 등록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const NotificationSettingsException(
        _deviceRegistrationErrorMessage,
      );
    }
  }

  Future<RegisteredDevice> _postDeviceWithAuthorizationRetry(
    DeviceRegistrationRequest registrationRequest,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = await _httpClient
          .postUrl(baseUri.resolve('/api/v1/devices'))
          .timeout(_notificationSettingsTimeout);
      final authorizationHeader = await authProvider
          .authorizationHeader()
          .timeout(_notificationSettingsTimeout);
      if (authorizationHeader != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          authorizationHeader,
        );
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(registrationRequest.toJson()));

      final response = await request.close().timeout(
        _notificationSettingsTimeout,
      );
      final body = await utf8
          .decodeStream(response)
          .timeout(_notificationSettingsTimeout);

      if (response.statusCode == HttpStatus.unauthorized &&
          authorizationHeader != null &&
          attempt == 0) {
        // 기기 등록도 익명 인증 사용자에 묶이므로 만료 시 한 번만 새 인증으로 재시도한다.
        await authProvider.invalidateAuthorization().timeout(
          _notificationSettingsTimeout,
        );
        continue;
      }

      if (response.statusCode < HttpStatus.ok ||
          response.statusCode >= HttpStatus.multipleChoices) {
        throw const NotificationSettingsException(
          _deviceRegistrationErrorMessage,
        );
      }

      return _registeredDeviceFromBody(body);
    }
    throw const NotificationSettingsException(_deviceRegistrationErrorMessage);
  }

  RegisteredDevice _registeredDeviceFromBody(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const NotificationSettingsException(
          _deviceRegistrationErrorMessage,
        );
      }

      final data = decoded['data'];
      if (data is! Map<String, Object?>) {
        throw const NotificationSettingsException(
          _deviceRegistrationErrorMessage,
        );
      }

      return RegisteredDevice.fromJson(data);
    } on NotificationSettingsException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '기기 알림 등록 응답 파싱 중 예외가 발생했습니다.',
      );
      throw const NotificationSettingsException(
        _deviceRegistrationErrorMessage,
      );
    }
  }
}

class NotificationSettingsException implements Exception {
  const NotificationSettingsException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum DevicePlatform {
  android('ANDROID'),
  ios('IOS');

  const DevicePlatform(this.apiValue);

  factory DevicePlatform.fromJson(String value) {
    return switch (value) {
      'ANDROID' => DevicePlatform.android,
      'IOS' => DevicePlatform.ios,
      _ => throw const NotificationSettingsException(
        _deviceRegistrationErrorMessage,
      ),
    };
  }

  final String apiValue;
}

class DeviceRegistrationRequest {
  const DeviceRegistrationRequest({
    required this.platform,
    required this.deviceToken,
  });

  final DevicePlatform platform;
  final String deviceToken;

  Map<String, Object?> toJson() {
    return {
      'platform': platform.apiValue,
      'deviceToken': deviceToken.trim(),
    };
  }
}

class RegisteredDevice {
  const RegisteredDevice({
    required this.userId,
    required this.platform,
    required this.deviceToken,
    required this.registeredAt,
  });

  factory RegisteredDevice.fromJson(Map<String, Object?> json) {
    return RegisteredDevice(
      userId: _requiredString(json, 'userId'),
      platform: DevicePlatform.fromJson(_requiredString(json, 'platform')),
      deviceToken: _requiredString(json, 'deviceToken'),
      registeredAt: _requiredString(json, 'registeredAt'),
    );
  }

  final String userId;
  final DevicePlatform platform;
  final String deviceToken;
  final String registeredAt;
}

class NotificationSettings {
  const NotificationSettings({
    required this.userId,
    required this.favoriteStationFacilityAlerts,
    required this.favoriteRouteFacilityAlerts,
    required this.reportStatusAlerts,
    required this.dataQualityAlerts,
    required this.updatedAt,
  });

  factory NotificationSettings.fromJson(Map<String, Object?> json) {
    return NotificationSettings(
      userId: _requiredString(json, 'userId'),
      favoriteStationFacilityAlerts: _requiredBool(
        json,
        'favoriteStationFacilityAlerts',
      ),
      favoriteRouteFacilityAlerts: _requiredBool(
        json,
        'favoriteRouteFacilityAlerts',
      ),
      reportStatusAlerts: _requiredBool(json, 'reportStatusAlerts'),
      dataQualityAlerts: _requiredBool(json, 'dataQualityAlerts'),
      updatedAt: _requiredString(json, 'updatedAt'),
    );
  }

  final String userId;
  final bool favoriteStationFacilityAlerts;
  final bool favoriteRouteFacilityAlerts;
  final bool reportStatusAlerts;
  final bool dataQualityAlerts;
  final String updatedAt;

  Map<String, Object?> toRequestJson() {
    return {
      'userId': userId,
      'favoriteStationFacilityAlerts': favoriteStationFacilityAlerts,
      'favoriteRouteFacilityAlerts': favoriteRouteFacilityAlerts,
      'reportStatusAlerts': reportStatusAlerts,
      'dataQualityAlerts': dataQualityAlerts,
    };
  }

  NotificationSettings copyWith({
    String? userId,
    bool? favoriteStationFacilityAlerts,
    bool? favoriteRouteFacilityAlerts,
    bool? reportStatusAlerts,
    bool? dataQualityAlerts,
    String? updatedAt,
  }) {
    return NotificationSettings(
      userId: userId ?? this.userId,
      favoriteStationFacilityAlerts:
          favoriteStationFacilityAlerts ?? this.favoriteStationFacilityAlerts,
      favoriteRouteFacilityAlerts:
          favoriteRouteFacilityAlerts ?? this.favoriteRouteFacilityAlerts,
      reportStatusAlerts: reportStatusAlerts ?? this.reportStatusAlerts,
      dataQualityAlerts: dataQualityAlerts ?? this.dataQualityAlerts,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum NotificationSettingsStatus { loading, ready, saving, failure }

class NotificationSettingsState {
  const NotificationSettingsState({
    required this.status,
    this.settings,
    this.message = '',
  });

  const NotificationSettingsState.loading()
    : status = NotificationSettingsStatus.loading,
      settings = null,
      message = '';

  final NotificationSettingsStatus status;
  final NotificationSettings? settings;
  final String message;

  bool get isSaving => status == NotificationSettingsStatus.saving;
}

class NotificationSettingsController extends ChangeNotifier {
  NotificationSettingsController({required this.repository});

  final NotificationSettingsRepository repository;

  NotificationSettingsState _state = const NotificationSettingsState.loading();
  bool _isDisposed = false;

  NotificationSettingsState get state => _state;

  Future<void> load() async {
    _emitState(const NotificationSettingsState.loading());

    try {
      final settings = await repository.getNotificationSettings();
      _emitState(
        NotificationSettingsState(
          status: NotificationSettingsStatus.ready,
          settings: settings,
        ),
      );
    } on NotificationSettingsException catch (error) {
      _emitFailure(error.message);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '알림 설정 화면 조회 처리 중 예외가 발생했습니다.',
      );
      _emitFailure(_notificationSettingsLoadErrorMessage);
    }
  }

  void updateFavoriteStationFacilityAlerts(bool value) {
    _updateSettings(
      (settings) => settings.copyWith(favoriteStationFacilityAlerts: value),
    );
  }

  void updateFavoriteRouteFacilityAlerts(bool value) {
    _updateSettings(
      (settings) => settings.copyWith(favoriteRouteFacilityAlerts: value),
    );
  }

  void updateReportStatusAlerts(bool value) {
    _updateSettings((settings) => settings.copyWith(reportStatusAlerts: value));
  }

  void updateDataQualityAlerts(bool value) {
    _updateSettings((settings) => settings.copyWith(dataQualityAlerts: value));
  }

  Future<void> save() async {
    final settings = _state.settings;
    if (settings == null || _state.isSaving) {
      return;
    }

    _emitState(
      NotificationSettingsState(
        status: NotificationSettingsStatus.saving,
        settings: settings,
      ),
    );

    try {
      final savedSettings = await repository.saveNotificationSettings(settings);
      _emitState(
        NotificationSettingsState(
          status: NotificationSettingsStatus.ready,
          settings: savedSettings,
          message: '알림 설정을 저장했습니다.',
        ),
      );
    } on NotificationSettingsException catch (error) {
      _emitState(
        NotificationSettingsState(
          status: NotificationSettingsStatus.ready,
          settings: settings,
          message: error.message,
        ),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '알림 설정 화면 저장 처리 중 예외가 발생했습니다.',
      );
      _emitState(
        NotificationSettingsState(
          status: NotificationSettingsStatus.ready,
          settings: settings,
          message: _notificationSettingsSaveErrorMessage,
        ),
      );
    }
  }

  void _updateSettings(
    NotificationSettings Function(NotificationSettings settings) update,
  ) {
    final settings = _state.settings;
    if (settings == null || _state.isSaving) {
      return;
    }
    _emitState(
      NotificationSettingsState(
        status: NotificationSettingsStatus.ready,
        settings: update(settings),
      ),
    );
  }

  void _emitFailure(String message) {
    _emitState(
      NotificationSettingsState(
        status: NotificationSettingsStatus.failure,
        message: message,
      ),
    );
  }

  void _emitState(NotificationSettingsState nextState) {
    if (_isDisposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({required this.repository, super.key});

  final NotificationSettingsRepository repository;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final NotificationSettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NotificationSettingsController(repository: widget.repository);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('알림 설정')),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final state = _controller.state;
            final settings = state.settings;
            if (state.status == NotificationSettingsStatus.failure &&
                settings == null) {
              return _NotificationSettingsFailure(
                message: state.message,
                onRetry: _controller.load,
              );
            }
            if (settings == null) {
              return const _NotificationSettingsLoading();
            }
            return _NotificationSettingsContent(
              state: state,
              onFavoriteStationFacilityAlertsChanged:
                  _controller.updateFavoriteStationFacilityAlerts,
              onFavoriteRouteFacilityAlertsChanged:
                  _controller.updateFavoriteRouteFacilityAlerts,
              onReportStatusAlertsChanged: _controller.updateReportStatusAlerts,
              onDataQualityAlertsChanged: _controller.updateDataQualityAlerts,
              onSave: _controller.save,
            );
          },
        ),
      ),
    );
  }
}

class _NotificationSettingsContent extends StatelessWidget {
  const _NotificationSettingsContent({
    required this.state,
    required this.onFavoriteStationFacilityAlertsChanged,
    required this.onFavoriteRouteFacilityAlertsChanged,
    required this.onReportStatusAlertsChanged,
    required this.onDataQualityAlertsChanged,
    required this.onSave,
  });

  final NotificationSettingsState state;
  final ValueChanged<bool> onFavoriteStationFacilityAlertsChanged;
  final ValueChanged<bool> onFavoriteRouteFacilityAlertsChanged;
  final ValueChanged<bool> onReportStatusAlertsChanged;
  final ValueChanged<bool> onDataQualityAlertsChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final settings = state.settings!;
    final isSaving = state.isSaving;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        _NotificationSwitchTile(
          key: const Key('notificationSwitch-favoriteStationFacilityAlerts'),
          title: '역 시설 알림',
          value: settings.favoriteStationFacilityAlerts,
          enabled: !isSaving,
          onChanged: onFavoriteStationFacilityAlertsChanged,
        ),
        _NotificationSwitchTile(
          key: const Key('notificationSwitch-favoriteRouteFacilityAlerts'),
          title: '경로 시설 알림',
          value: settings.favoriteRouteFacilityAlerts,
          enabled: !isSaving,
          onChanged: onFavoriteRouteFacilityAlertsChanged,
        ),
        _NotificationSwitchTile(
          key: const Key('notificationSwitch-reportStatusAlerts'),
          title: '신고 처리 알림',
          value: settings.reportStatusAlerts,
          enabled: !isSaving,
          onChanged: onReportStatusAlertsChanged,
        ),
        _NotificationSwitchTile(
          key: const Key('notificationSwitch-dataQualityAlerts'),
          title: '정보 갱신 알림',
          value: settings.dataQualityAlerts,
          enabled: !isSaving,
          onChanged: onDataQualityAlertsChanged,
        ),
        const SizedBox(height: 12),
        Semantics(
          label: isSaving ? '알림 설정 저장 중' : '알림 설정 저장',
          child: FilledButton.icon(
            key: const Key('notificationSettingsSaveButton'),
            onPressed: isSaving ? null : onSave,
            icon: isSaving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(isSaving ? '저장 중' : '저장'),
          ),
        ),
        if (state.message.isNotEmpty) ...[
          const SizedBox(height: 16),
          Semantics(
            container: true,
            excludeSemantics: true,
            liveRegion: true,
            label: state.message,
            child: Text(
              state.message,
              key: const Key('notificationSettingsMessage'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NotificationSwitchTile extends StatelessWidget {
  const _NotificationSwitchTile({
    required super.key,
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFD5E2E4)),
      ),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        label: '$title ${value ? '켜짐' : '꺼짐'}',
        toggled: value,
        enabled: enabled,
        onTap: enabled ? () => onChanged(!value) : null,
        child: SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          activeThumbColor: colorScheme.primary,
          title: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF102A2C),
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
          value: value,
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

class _NotificationSettingsLoading extends StatelessWidget {
  const _NotificationSettingsLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        liveRegion: true,
        label: '알림 설정 불러오는 중',
        child: const CircularProgressIndicator(),
      ),
    );
  }
}

class _NotificationSettingsFailure extends StatelessWidget {
  const _NotificationSettingsFailure({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      children: [
        Semantics(
          liveRegion: true,
          label: message,
          child: Text(
            message,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF102A2C),
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('notificationSettingsRetryButton'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('다시 시도'),
        ),
      ],
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required notification setting field: $key');
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('Missing required notification setting boolean: $key');
}
