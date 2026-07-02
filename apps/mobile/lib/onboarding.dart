import 'dart:convert';

import 'package:flutter/material.dart';

import 'accessible_design.dart';
import 'mobility_profile.dart';
import 'mobile_error_reporter.dart';
import 'notification_settings.dart';
import 'secure_key_value_storage.dart';
import 'station_search.dart';

const _onboardingResultStorageKey = 'easysubway.onboarding.result';
const _onboardingNotificationFailureNextAction = '나중에 알림 설정에서 다시 켤 수 있습니다.';

abstract class OnboardingResultStore {
  Future<OnboardingResult?> readResult();

  Future<void> saveResult(OnboardingResult result);

  Future<void> clearResult();
}

class SecureOnboardingResultStore implements OnboardingResultStore {
  const SecureOnboardingResultStore({
    this.storage = const FlutterSecureKeyValueStorage(),
  });

  final SecureKeyValueStorage storage;

  @override
  Future<OnboardingResult?> readResult() async {
    try {
      final value = await storage.read(key: _onboardingResultStorageKey);
      if (value == null) {
        return null;
      }
      return OnboardingResult.decode(value);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '저장된 온보딩 설정을 읽는 중 예외가 발생했습니다.',
      );
      await _clearResultAfterReadFailure();
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

  Future<void> _clearResultAfterReadFailure() async {
    try {
      await clearResult();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '손상된 온보딩 설정을 지우는 중 예외가 발생했습니다.',
      );
    }
  }
}

class OnboardingViewPreferences {
  const OnboardingViewPreferences({
    required this.largeTextEnabled,
    required this.highContrastEnabled,
    required this.simpleViewEnabled,
  });

  const OnboardingViewPreferences.defaults()
    : largeTextEnabled = false,
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

class StartScreen extends StatelessWidget {
  const StartScreen({required this.onStart, super.key});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          color: EasySubwayAccessibleColors.primary,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final topGap = (constraints.maxHeight * 0.34).clamp(84.0, 212.0);
              final bottomGap = 35 + MediaQuery.viewPaddingOf(context).bottom;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(24, 48, 24, bottomGap),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: topGap),
                          Semantics(
                            header: true,
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '빠른 길보다,\n'),
                                  TextSpan(
                                    text: '갈 수 있는 길',
                                    style: TextStyle(color: Color(0xFFB8F4DF)),
                                  ),
                                  TextSpan(text: '을\n먼저 안내해요.'),
                                ],
                              ),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                height: 1.12,
                              ),
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const Key('startScreenStartButton'),
                              onPressed: onStart,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF0B3B42),
                                minimumSize: const Size.fromHeight(60),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('쉬운 지하철 시작하기'),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class OnboardingIntroScreen extends StatelessWidget {
  const OnboardingIntroScreen({
    required this.onConfigure,
    required this.onSkip,
    super.key,
  });

  // Repository contract marker: 먼저 이동 조건을 골라 주세요
  final VoidCallback onConfigure;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('쉬운 지하철')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            const _IntroVisual(),
            const SizedBox(height: 25),
            Semantics(
              header: true,
              child: Text(
                '계단 없는 길을\n먼저 찾습니다',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w900,
                  height: 1.25,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const _IntroInfoCard(),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('onboardingIntroConfigureButton'),
              onPressed: onConfigure,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('이동 조건 설정'),
            ),
            const SizedBox(height: 9),
            OutlinedButton(
              key: const Key('onboardingIntroSkipButton'),
              onPressed: onSkip,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('기본 설정으로 시작'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroVisual extends StatelessWidget {
  const _IntroVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 230,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: EasySubwayAccessibleColors.surface,
          border: Border.all(color: EasySubwayAccessibleColors.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Stack(
          children: [
            Positioned(
              left: 28,
              top: 38,
              child: _IntroIcon(
                icon: Icons.accessible_forward,
                color: EasySubwayAccessibleColors.mint,
              ),
            ),
            Positioned(
              right: 30,
              top: 80,
              child: _IntroIcon(
                icon: Icons.elevator_outlined,
                color: EasySubwayAccessibleColors.primary,
              ),
            ),
            Positioned(
              left: 117,
              bottom: 26,
              child: _IntroIcon(
                icon: Icons.route,
                color: Colors.white,
                backgroundColor: EasySubwayAccessibleColors.primary,
                size: 94,
                iconSize: 44,
                radius: 29,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroIcon extends StatelessWidget {
  const _IntroIcon({
    required this.icon,
    required this.color,
    this.backgroundColor = Colors.white,
    this.size = 86,
    this.iconSize = 43,
    this.radius = 27,
  });

  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final double size;
  final double iconSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16071B2F),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }
}

class _IntroInfoCard extends StatelessWidget {
  const _IntroInfoCard();

  @override
  Widget build(BuildContext context) {
    return const _IntroCard(
      child: Column(
        children: [
          _IntroInfoRow(
            icon: Icons.elevator_outlined,
            title: '엘리베이터 확인',
            subtitle: '고장 시설을 피해 안내',
          ),
          _IntroDivider(),
          _IntroInfoRow(
            icon: Icons.route_outlined,
            title: '걷기와 환승 줄이기',
            subtitle: '내 이동 조건에 맞춰 안내',
          ),
          _IntroDivider(),
          _IntroInfoRow(
            icon: Icons.map_outlined,
            title: '인터넷 없이 이용',
            subtitle: '노선도와 역 정보 확인',
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: EasySubwayAccessibleColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _IntroInfoRow extends StatelessWidget {
  const _IntroInfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFDFF7EF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: SizedBox(
            width: 43,
            height: 43,
            child: Icon(icon, color: const Color(0xFF0A705A), size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF647686),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IntroDivider extends StatelessWidget {
  const _IntroDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 13),
      child: Divider(height: 1, color: Color(0xFFE0E7EC)),
    );
  }
}

class _OnboardingStepIndicator extends StatelessWidget {
  const _OnboardingStepIndicator({
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var step = 1; step <= totalSteps; step++) ...[
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: step <= currentStep
                        ? const Color(0xFF0D8A6D)
                        : const Color(0xFFDBE3E9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const SizedBox(height: 5),
                ),
              ),
              if (step != totalSteps) const SizedBox(width: 4),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '$currentStep / $totalSteps',
          textAlign: TextAlign.right,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF647686),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PermissionInfoCard extends StatelessWidget {
  const _PermissionInfoCard({
    required this.locationSelected,
    required this.notificationSelected,
    required this.onLocationChanged,
    required this.onNotificationChanged,
  });

  final bool locationSelected;
  final bool notificationSelected;
  final ValueChanged<bool> onLocationChanged;
  final ValueChanged<bool> onNotificationChanged;

  @override
  Widget build(BuildContext context) {
    return _IntroCard(
      child: Column(
        children: [
          _PermissionInfoRow(
            icon: Icons.location_on_outlined,
            title: '현재 위치',
            subtitle: '가까운 역 찾기',
            mint: true,
            value: locationSelected,
            onChanged: onLocationChanged,
          ),
          const _IntroDivider(),
          _PermissionInfoRow(
            icon: Icons.notifications_none,
            title: '알림',
            subtitle: '시설 고장·복구 알림',
            value: notificationSelected,
            onChanged: onNotificationChanged,
          ),
        ],
      ),
    );
  }
}

class _PermissionInfoRow extends StatelessWidget {
  const _PermissionInfoRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.mint = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool mint;

  @override
  Widget build(BuildContext context) {
    final iconColor = mint ? const Color(0xFF0A705A) : const Color(0xFF17527C);
    final iconBackground = mint
        ? const Color(0xFFDFF7EF)
        : const Color(0xFFEEF3F6);

    return Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: iconBackground,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SizedBox(
            width: 43,
            height: 43,
            child: Icon(icon, color: iconColor, size: 22),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: EasySubwayAccessibleColors.text,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF647686),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        Semantics(
          label: '$title ${value ? '켜짐' : '꺼짐'}',
          toggled: value,
          onTap: () => onChanged(!value),
          child: ExcludeSemantics(
            child: Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: const Color(0xFF0D8A6D),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFC8D3DC),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ),
        ),
      ],
    );
  }
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
  int _currentStep = 0;
  bool _locationPermissionSelected = false;
  bool _notificationPermissionSelected = false;
  bool _showNotificationPermissionFailureNextAction = false;

  @override
  Widget build(BuildContext context) {
    final selectedProfile = _selectedProfile;
    final textTheme = Theme.of(context).textTheme;
    final listBottomPadding = _currentStep == 2 ? 32.0 : 104.0;
    final profileOptions = [
      mobilityProfileOptions.firstWhere((profile) => profile.id == 'elderly'),
      mobilityProfileOptions.firstWhere(
        (profile) => profile.id == 'wheelchair',
      ),
      mobilityProfileOptions.firstWhere((profile) => profile.id == 'stroller'),
      mobilityProfileOptions.firstWhere((profile) => profile.id == 'pregnant'),
      mobilityProfileOptions.firstWhere((profile) => profile.id == 'injured'),
      mobilityProfileOptions.firstWhere((profile) => profile.id == 'luggage'),
    ];

    final onNext = selectedProfile == null
        ? null
        : () {
            if (_currentStep == 0) {
              setState(() => _currentStep = 1);
              return;
            }
            if (_currentStep == 1) {
              setState(() => _currentStep = 2);
              return;
            }
            _completeOnboarding();
          };

    return Scaffold(
      appBar: AppBar(
        title: const Text('쉬운 지하철'),
        leading: _currentStep == 0
            ? null
            : IconButton(
                tooltip: '이전 단계',
                onPressed: _goBack,
                icon: const Icon(Icons.arrow_back),
              ),
      ),
      bottomNavigationBar: _currentStep == 2
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton(
                key: const Key('onboardingDoneButton'),
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('다음'),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, listBottomPadding),
          children: _currentStep == 0
              ? [
                  const _OnboardingStepIndicator(currentStep: 1, totalSteps: 3),
                  const SizedBox(height: 15),
                  Semantics(
                    header: true,
                    child: Text(
                      '어떤 도움이 필요한가요?',
                      style: textTheme.headlineSmall?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final profile in profileOptions)
                    _OnboardingProfileCard(
                      profile: profile,
                      selected: profile.id == selectedProfile?.id,
                      onTap: () {
                        setState(() {
                          _selectedProfile = profile;
                        });
                      },
                    ),
                ]
              : _currentStep == 1
              ? [
                  const _OnboardingStepIndicator(currentStep: 2, totalSteps: 3),
                  const SizedBox(height: 15),
                  Semantics(
                    header: true,
                    child: Text(
                      '적용할 조건을 확인하세요',
                      style: textTheme.headlineSmall?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _OnboardingPreferenceCard(
                    children: [
                      _OnboardingConditionRow(
                        key: const Key('onboardingRoutePreference-avoidStairs'),
                        title: '계단 피하기',
                        subtitle: '계단 없는 길',
                        enabled: selectedProfile?.avoidStairs ?? true,
                      ),
                      const _OnboardingPreferenceDivider(),
                      _OnboardingConditionRow(
                        key: const Key(
                          'onboardingRoutePreference-requireElevator',
                        ),
                        title: '엘리베이터 이용',
                        subtitle: '엘리베이터 연결',
                        enabled: selectedProfile?.requireElevator ?? true,
                      ),
                      const _OnboardingPreferenceDivider(),
                      _OnboardingConditionRow(
                        key: const Key(
                          'onboardingRoutePreference-minimizeTransfers',
                        ),
                        title: '환승 줄이기',
                        subtitle: '갈아타는 횟수 줄이기',
                        enabled: selectedProfile?.minimizeTransfers ?? true,
                      ),
                      const _OnboardingPreferenceDivider(),
                      _OnboardingConditionRow(
                        key: const Key(
                          'onboardingRoutePreference-avoidLongWalks',
                        ),
                        title: '걷는 거리 줄이기',
                        subtitle: '오래 걷는 길 피하기',
                        enabled: selectedProfile?.avoidLongWalks ?? true,
                      ),
                    ],
                  ),
                  _OnboardingPreferenceCard(
                    children: [
                      _OnboardingViewPreferenceSwitch(
                        key: const Key('onboardingPreference-highContrast'),
                        title: '고대비',
                        subtitle: '글자와 배경 대비 강화',
                        value: _preferences.highContrastEnabled,
                        onChanged: (value) {
                          setState(() {
                            _preferences = _preferences.copyWith(
                              highContrastEnabled: value,
                            );
                          });
                        },
                      ),
                      const _OnboardingPreferenceDivider(),
                      _OnboardingViewPreferenceSwitch(
                        key: const Key('onboardingPreference-simpleView'),
                        title: '간편 보기',
                        subtitle: '꼭 필요한 안내부터 보여요',
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
                ]
              : [
                  const _OnboardingStepIndicator(currentStep: 3, totalSteps: 3),
                  const SizedBox(height: 15),
                  Semantics(
                    header: true,
                    child: Text(
                      '위치와 알림은 나중에도 켤 수 있어요',
                      style: textTheme.headlineSmall?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w900,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _PermissionInfoCard(
                    locationSelected: _locationPermissionSelected,
                    notificationSelected: _notificationPermissionSelected,
                    onLocationChanged: (value) =>
                        setState(() => _locationPermissionSelected = value),
                    onNotificationChanged: (value) =>
                        setState(() => _notificationPermissionSelected = value),
                  ),
                  if (_showNotificationPermissionFailureNextAction) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      key: const Key('onboardingNotificationFailureNextAction'),
                      container: true,
                      excludeSemantics: true,
                      liveRegion: true,
                      label: '도움말, $_onboardingNotificationFailureNextAction',
                      child: Text(
                        _onboardingNotificationFailureNextAction,
                        style: textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF506B6F),
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    key: const Key('onboardingPermissionAllowButton'),
                    onPressed:
                        _locationPermissionSelected ||
                            _notificationPermissionSelected
                        ? _handlePermissionAllow
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('선택한 기능 설정하고 시작'),
                  ),
                  const SizedBox(height: 9),
                  OutlinedButton(
                    key: const Key('onboardingPermissionSkipButton'),
                    onPressed: _completeOnboarding,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('나중에 설정'),
                  ),
                ],
        ),
      ),
    );
  }

  void _goBack() {
    if (_currentStep == 0) {
      return;
    }
    setState(() => _currentStep -= 1);
  }

  void _completeOnboarding() {
    final selectedProfile = _selectedProfile;
    if (selectedProfile == null) {
      return;
    }
    widget.onCompleted(
      OnboardingResult(profile: selectedProfile, preferences: _preferences),
    );
  }

  Future<void> _handlePermissionAllow() async {
    final permissionsReady = await _prepareSelectedPermissions();
    if (!mounted) {
      return;
    }
    if (!permissionsReady) {
      return;
    }
    _completeOnboarding();
  }

  Future<bool> _prepareSelectedPermissions() async {
    if (_locationPermissionSelected) {
      await _prepareLocationPermission();
    }
    if (!mounted) {
      return false;
    }
    if (_notificationPermissionSelected) {
      return await _prepareNotificationPermission();
    }
    return true;
  }

  Future<void> _prepareLocationPermission() async {
    final locationProvider = widget.locationProvider;
    if (locationProvider == null) {
      return;
    }
    try {
      await locationProvider.currentLocation();
    } on CurrentLocationException catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '온보딩 현재 위치 권한 준비 중 예외가 발생했습니다.',
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '온보딩 현재 위치 권한 준비 중 알 수 없는 예외가 발생했습니다.',
      );
    }
  }

  Future<bool> _prepareNotificationPermission() async {
    final notificationPermissionProvider =
        widget.notificationPermissionProvider;
    if (notificationPermissionProvider == null) {
      return true;
    }
    try {
      await notificationPermissionProvider.requestNotificationPermission();
      if (mounted) {
        setState(() => _showNotificationPermissionFailureNextAction = false);
      }
      return true;
    } on NotificationSettingsException catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '온보딩 알림 켜기 준비 중 예외가 발생했습니다.',
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '온보딩 알림 켜기 준비 중 알 수 없는 예외가 발생했습니다.',
      );
    }
    if (mounted) {
      setState(() => _showNotificationPermissionFailureNextAction = true);
    }
    return false;
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
    const primaryColor = Color(0xFF0D8A6D);
    final borderColor = selected ? primaryColor : const Color(0xFFDBE3E9);
    final backgroundColor = selected ? const Color(0xFFEAF8F3) : Colors.white;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Semantics(
        label: profile.semanticsLabel(selected),
        selected: selected,
        button: true,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: backgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
              side: BorderSide(color: borderColor, width: selected ? 2 : 1),
            ),
            child: InkWell(
              key: Key('onboardingProfileCard-${profile.id}'),
              borderRadius: BorderRadius.circular(17),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 78),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFDFF7EF)
                              : const Color(0xFFEEF3F6),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: Icon(
                            profile.icon,
                            color: selected
                                ? primaryColor
                                : const Color(0xFF17527C),
                            size: 23,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _profileDisplayTitle(profile),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: EasySubwayAccessibleColors.text,
                                    fontWeight: FontWeight.w900,
                                    height: 1.25,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _profileDisplaySummary(profile),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: const Color(0xFF647686),
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      _ProfileRadio(selected: selected),
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

  String _profileDisplayTitle(MobilityProfileOption profile) {
    return profile.title;
  }

  String _profileDisplaySummary(MobilityProfileOption profile) {
    return switch (profile.id) {
      'elderly' => '걷기와 환승 줄이기',
      'wheelchair' => '계단 없는 길',
      'stroller' => '엘리베이터 우선',
      'pregnant' => '걷는 거리 줄이기',
      'injured' => '계단 피하기',
      'luggage' => '넓은 길 우선',
      _ => profile.summary,
    };
  }
}

class _ProfileRadio extends StatelessWidget {
  const _ProfileRadio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? const Color(0xFF0D8A6D) : const Color(0xFFC8D3DC),
          width: 2,
        ),
      ),
      child: SizedBox(
        width: 22,
        height: 22,
        child: selected
            ? const Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFF0D8A6D),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(width: 10, height: 10),
                ),
              )
            : null,
      ),
    );
  }
}

class _OnboardingPreferenceCard extends StatelessWidget {
  const _OnboardingPreferenceCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDBE3E9)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: children),
      ),
    );
  }
}

class _OnboardingConditionRow extends StatelessWidget {
  const _OnboardingConditionRow({
    required super.key,
    required this.title,
    required this.subtitle,
    required this.enabled,
  });

  final String title;
  final String subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final state = enabled ? '켜짐' : '꺼짐';

    return Semantics(
      container: true,
      label: '$title $state, $subtitle',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF647686),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: enabled
                      ? const Color(0xFFDFF7EF)
                      : const Color(0xFFEEF3F6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 72,
                    minHeight: 36,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    child: Center(
                      child: Text(
                        state,
                        style: TextStyle(
                          color: enabled
                              ? const Color(0xFF0D8A6D)
                              : const Color(0xFF647686),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingViewPreferenceSwitch extends StatelessWidget {
  const _OnboardingViewPreferenceSwitch({
    required super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$title ${value ? '켜짐' : '꺼짐'}, $subtitle',
      toggled: value,
      onTap: () => onChanged(!value),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF647686),
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: const Color(0xFF0D8A6D),
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFC8D3DC),
                materialTapTargetSize: MaterialTapTargetSize.padded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPreferenceDivider extends StatelessWidget {
  const _OnboardingPreferenceDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: Color(0xFFDBE3E9));
  }
}
