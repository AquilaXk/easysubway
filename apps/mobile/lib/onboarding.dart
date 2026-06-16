import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'mobility_profile.dart';
import 'mobile_error_reporter.dart';
import 'notification_settings.dart';
import 'station_search.dart';

const _onboardingResultStorageKey = 'easysubway.onboarding.result';

abstract class OnboardingResultStore {
  Future<OnboardingResult?> readResult();

  Future<void> saveResult(OnboardingResult result);

  Future<void> clearResult();
}

class SecureOnboardingResultStore implements OnboardingResultStore {
  const SecureOnboardingResultStore({
    this.storage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage storage;

  @override
  Future<OnboardingResult?> readResult() async {
    final value = await storage.read(key: _onboardingResultStorageKey);
    if (value == null) {
      return null;
    }

    try {
      return OnboardingResult.decode(value);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '저장된 온보딩 설정을 읽는 중 예외가 발생했습니다.',
      );
      await clearResult();
      return null;
    }
  }

  @override
  Future<void> saveResult(OnboardingResult result) async {
    await storage.write(
      key: _onboardingResultStorageKey,
      value: result.encode(),
    );
  }

  @override
  Future<void> clearResult() async {
    await storage.delete(key: _onboardingResultStorageKey);
  }
}

class OnboardingViewPreferences {
  const OnboardingViewPreferences({
    required this.largeTextEnabled,
    required this.highContrastEnabled,
    required this.simpleViewEnabled,
  });

  const OnboardingViewPreferences.defaults()
    : largeTextEnabled = true,
      highContrastEnabled = false,
      simpleViewEnabled = true;

  factory OnboardingViewPreferences.fromJson(Map<String, Object?> json) {
    final largeTextEnabled = json['largeTextEnabled'];
    final highContrastEnabled = json['highContrastEnabled'];
    final simpleViewEnabled = json['simpleViewEnabled'];
    // 손상된 저장값이 접근성 기본값을 조용히 끄지 않도록 타입을 엄격히 확인한다.
    if (largeTextEnabled is! bool ||
        highContrastEnabled is! bool ||
        simpleViewEnabled is! bool) {
      throw const FormatException('Invalid onboarding preferences payload');
    }

    return OnboardingViewPreferences(
      largeTextEnabled: largeTextEnabled,
      highContrastEnabled: highContrastEnabled,
      simpleViewEnabled: simpleViewEnabled,
    );
  }

  final bool largeTextEnabled;
  final bool highContrastEnabled;
  final bool simpleViewEnabled;

  OnboardingViewPreferences copyWith({
    bool? largeTextEnabled,
    bool? highContrastEnabled,
    bool? simpleViewEnabled,
  }) {
    return OnboardingViewPreferences(
      largeTextEnabled: largeTextEnabled ?? this.largeTextEnabled,
      highContrastEnabled: highContrastEnabled ?? this.highContrastEnabled,
      simpleViewEnabled: simpleViewEnabled ?? this.simpleViewEnabled,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'largeTextEnabled': largeTextEnabled,
      'highContrastEnabled': highContrastEnabled,
      'simpleViewEnabled': simpleViewEnabled,
    };
  }
}

class OnboardingResult {
  const OnboardingResult({required this.profile, required this.preferences});

  factory OnboardingResult.fromJson(Map<String, Object?> json) {
    final profileId = json['profileId'];
    final preferences = json['preferences'];
    if (profileId is! String || preferences is! Map<String, Object?>) {
      throw const FormatException('Invalid onboarding storage payload');
    }

    final profile = mobilityProfileOptions.firstWhere(
      (option) => option.id == profileId,
      orElse: () => throw const FormatException('Invalid onboarding profile'),
    );

    return OnboardingResult(
      profile: profile,
      preferences: OnboardingViewPreferences.fromJson(preferences),
    );
  }

  factory OnboardingResult.decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid onboarding storage payload');
    }
    return OnboardingResult.fromJson(decoded);
  }

  final MobilityProfileOption profile;
  final OnboardingViewPreferences preferences;

  Map<String, Object?> toJson() {
    return {'profileId': profile.id, 'preferences': preferences.toJson()};
  }

  String encode() {
    return jsonEncode(toJson());
  }
}

class OnboardingState {
  const OnboardingState.initial() : result = null;

  const OnboardingState.completed({required this.result});

  final OnboardingResult? result;

  bool get isCompleted => result != null;
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.onCompleted,
    this.locationProvider,
    this.notificationPermissionProvider,
    super.key,
  });

  final ValueChanged<OnboardingResult> onCompleted;
  final CurrentLocationProvider? locationProvider;
  final NotificationPermissionProvider? notificationPermissionProvider;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  MobilityProfileOption? _selectedProfile;
  OnboardingViewPreferences _preferences =
      const OnboardingViewPreferences.defaults();
  String _locationMessage = '';
  bool _isLocationFailure = false;
  bool _isCheckingLocation = false;
  bool _isOpeningLocationSettings = false;
  String _notificationMessage = '';
  bool _isNotificationFailure = false;
  bool _isRequestingNotificationPermission = false;

  @override
  Widget build(BuildContext context) {
    final selectedProfile = _selectedProfile;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('쉬운 지하철')),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: FilledButton.icon(
          key: const Key('onboardingDoneButton'),
          onPressed: selectedProfile == null
              ? null
              : () {
                  widget.onCompleted(
                    OnboardingResult(
                      profile: selectedProfile,
                      preferences: _preferences,
                    ),
                  );
                },
          icon: const Icon(Icons.check),
          label: const Text('시작하기'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Semantics(
              header: true,
              child: Text(
                '먼저 이동 조건을 골라 주세요',
                style: textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '이동 조건',
              style: textTheme.titleLarge?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final profile in mobilityProfileOptions)
              _OnboardingProfileCard(
                profile: profile,
                selected: profile.id == selectedProfile?.id,
                onTap: () {
                  setState(() {
                    _selectedProfile = profile;
                  });
                },
              ),
            if (widget.locationProvider != null) ...[
              const SizedBox(height: 12),
              Text(
                '현재 위치',
                style: textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              _OnboardingLocationSection(
                message: _locationMessage,
                isFailure: _isLocationFailure,
                isChecking: _isCheckingLocation,
                isOpeningSettings: _isOpeningLocationSettings,
                isBlocked: _isRequestingNotificationPermission,
                onPrepareLocation: _prepareLocation,
                onOpenSettings: _openLocationSettings,
              ),
            ],
            if (widget.notificationPermissionProvider != null) ...[
              const SizedBox(height: 12),
              Text(
                '알림',
                style: textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              _OnboardingNotificationSection(
                message: _notificationMessage,
                isFailure: _isNotificationFailure,
                isRequesting: _isRequestingNotificationPermission,
                isBlocked: _isCheckingLocation || _isOpeningLocationSettings,
                onPrepareNotification: _prepareNotification,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              '보기 설정',
              style: textTheme.titleLarge?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            _OnboardingPreferenceSwitch(
              key: const Key('onboardingPreference-largeText'),
              title: '큰 글씨',
              value: _preferences.largeTextEnabled,
              onChanged: (value) {
                setState(() {
                  _preferences = _preferences.copyWith(largeTextEnabled: value);
                });
              },
            ),
            _OnboardingPreferenceSwitch(
              key: const Key('onboardingPreference-highContrast'),
              title: '고대비',
              value: _preferences.highContrastEnabled,
              onChanged: (value) {
                setState(() {
                  _preferences = _preferences.copyWith(
                    highContrastEnabled: value,
                  );
                });
              },
            ),
            _OnboardingPreferenceSwitch(
              key: const Key('onboardingPreference-simpleView'),
              title: '단순 보기',
              value: _preferences.simpleViewEnabled,
              onChanged: (value) {
                setState(() {
                  _preferences = _preferences.copyWith(
                    simpleViewEnabled: value,
                  );
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _prepareLocation() async {
    final locationProvider = widget.locationProvider;
    if (locationProvider == null ||
        _isCheckingLocation ||
        _isOpeningLocationSettings ||
        _isRequestingNotificationPermission) {
      return;
    }
    setState(() {
      _isCheckingLocation = true;
      _locationMessage = '';
      _isLocationFailure = false;
    });
    try {
      // 온보딩에서는 좌표를 저장하지 않고, 이후 주변 역 찾기에서 바로 쓸 권한과 GPS 상태만 준비한다.
      await locationProvider.currentLocation();
      if (!mounted) {
        return;
      }
      setState(() {
        _locationMessage = '위치 준비 완료';
        _isLocationFailure = false;
      });
    } on CurrentLocationException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _locationMessage = error.message;
        _isLocationFailure = true;
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '온보딩 현재 위치 준비 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _locationMessage = '현재 위치를 확인하지 못했습니다.';
        _isLocationFailure = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isCheckingLocation = false);
      }
    }
  }

  Future<void> _openLocationSettings() async {
    final locationProvider = widget.locationProvider;
    if (locationProvider == null ||
        _isOpeningLocationSettings ||
        _isCheckingLocation ||
        _isRequestingNotificationPermission) {
      return;
    }
    setState(() => _isOpeningLocationSettings = true);
    try {
      await locationProvider.openLocationSettings();
    } finally {
      if (mounted) {
        setState(() => _isOpeningLocationSettings = false);
      }
    }
  }

  Future<void> _prepareNotification() async {
    final notificationPermissionProvider =
        widget.notificationPermissionProvider;
    if (notificationPermissionProvider == null ||
        _isRequestingNotificationPermission ||
        _isCheckingLocation ||
        _isOpeningLocationSettings) {
      return;
    }
    setState(() {
      _isRequestingNotificationPermission = true;
      _notificationMessage = '';
      _isNotificationFailure = false;
    });
    try {
      // 온보딩에서는 토큰을 등록하지 않고, 이후 알림 설정에서 쓸 기기 권한만 준비한다.
      final status = await notificationPermissionProvider
          .requestNotificationPermission();
      if (!mounted) {
        return;
      }
      setState(() {
        _notificationMessage = status == NotificationPermissionStatus.granted
            ? '알림 준비 완료'
            : '설정에서 알림 권한을 켜 주세요.';
        _isNotificationFailure = status != NotificationPermissionStatus.granted;
      });
    } on NotificationSettingsException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notificationMessage = error.message;
        _isNotificationFailure = true;
      });
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '온보딩 알림 권한 준비 중 예외가 발생했습니다.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _notificationMessage = '알림 권한을 확인하지 못했습니다.';
        _isNotificationFailure = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isRequestingNotificationPermission = false);
      }
    }
  }
}

class _OnboardingLocationSection extends StatelessWidget {
  const _OnboardingLocationSection({
    required this.message,
    required this.isFailure,
    required this.isChecking,
    required this.isOpeningSettings,
    required this.isBlocked,
    required this.onPrepareLocation,
    required this.onOpenSettings,
  });

  final String message;
  final bool isFailure;
  final bool isChecking;
  final bool isOpeningSettings;
  final bool isBlocked;
  final VoidCallback onPrepareLocation;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '가까운 역을 자동으로 찾으려면 GPS가 필요합니다.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF29484B),
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('onboardingLocationButton'),
          onPressed: isChecking || isOpeningSettings || isBlocked
              ? null
              : onPrepareLocation,
          icon: isChecking
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.my_location),
          label: const Text('위치 켜기'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 10),
          _OnboardingStatusMessage(message: message, isFailure: isFailure),
        ],
        if (isFailure) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('onboardingOpenLocationSettingsButton'),
            onPressed: isOpeningSettings || isChecking || isBlocked
                ? null
                : onOpenSettings,
            icon: isOpeningSettings
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.settings),
            label: const Text('위치 설정 열기'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _OnboardingNotificationSection extends StatelessWidget {
  const _OnboardingNotificationSection({
    required this.message,
    required this.isFailure,
    required this.isRequesting,
    required this.isBlocked,
    required this.onPrepareNotification,
  });

  final String message;
  final bool isFailure;
  final bool isRequesting;
  final bool isBlocked;
  final VoidCallback onPrepareNotification;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '시설 고장, 신고 결과, 공사 안내를 알려드려요.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF29484B),
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('onboardingNotificationButton'),
          onPressed: isRequesting || isBlocked ? null : onPrepareNotification,
          icon: isRequesting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.notifications_active_outlined),
          label: const Text('알림 켜기'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(60),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        if (message.isNotEmpty) ...[
          const SizedBox(height: 10),
          _OnboardingStatusMessage(message: message, isFailure: isFailure),
        ],
      ],
    );
  }
}

class _OnboardingStatusMessage extends StatelessWidget {
  const _OnboardingStatusMessage({
    required this.message,
    required this.isFailure,
  });

  final String message;
  final bool isFailure;

  @override
  Widget build(BuildContext context) {
    final color = isFailure ? const Color(0xFF8A4B00) : const Color(0xFF006D77);
    final icon = isFailure ? Icons.error_outline : Icons.check_circle_outline;

    return Semantics(
      label: message,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingProfileCard extends StatelessWidget {
  const _OnboardingProfileCard({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final MobilityProfileOption profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = selected
        ? colorScheme.primary
        : const Color(0xFFD5E2E4);
    final backgroundColor = selected ? const Color(0xFFE6F2F0) : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: profile.semanticsLabel(selected),
        selected: selected,
        button: true,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: borderColor, width: selected ? 2 : 1),
            ),
            child: InkWell(
              key: Key('onboardingProfileCard-${profile.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 76),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(profile.icon, color: colorScheme.primary, size: 34),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              profile.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: const Color(0xFF102A2C),
                                    fontWeight: FontWeight.w900,
                                    height: 1.25,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              profile.summary,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: const Color(0xFF29484B),
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(Icons.check_circle, color: colorScheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPreferenceSwitch extends StatelessWidget {
  const _OnboardingPreferenceSwitch({
    required super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final state = value ? '켜짐' : '꺼짐';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        label: '$title $state',
        toggled: value,
        onTap: () => onChanged(!value),
        child: ExcludeSemantics(
          child: SwitchListTile(
            value: value,
            onChanged: onChanged,
            title: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w800,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFD5E2E4)),
            ),
          ),
        ),
      ),
    );
  }
}
