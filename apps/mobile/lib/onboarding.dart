import 'dart:convert';

import 'package:flutter/material.dart';

import 'accessible_design.dart';
import 'design_tokens.dart';
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

/// 화면 1 — 시작. 핵심 가치 한 줄(큰 타이틀) + 단일 CTA.
///
/// #1936: 부연 설명 문장은 전면 삭제한다. 상단을 크게 비우고, 가치 카피를
/// titleLarge 급 다크 잉크로 두 줄만 두고, 하단에 각진(radius 8) 무채색 CTA를
/// 고정한다. 블록·그림자·pill 없음.
class StartScreen extends StatelessWidget {
  const StartScreen({required this.onStart, super.key});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EasySubwayAccessibleColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 상단 ~35%를 비워 애플식 여백을 만든다.
            final topGap = (constraints.maxHeight * 0.35).clamp(96.0, 240.0);
            final bottomGap =
                EasySubwaySpacing.xxl +
                MediaQuery.viewPaddingOf(context).bottom;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      EasySubwaySpacing.xl,
                      EasySubwaySpacing.xxl,
                      EasySubwaySpacing.xl,
                      bottomGap,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: topGap),
                        Semantics(
                          header: true,
                          child: const Text(
                            // 핵심 가치 한 줄. 부연 설명("먼저 안내해요") 삭제(#1936).
                            // 강조도 무채색 잉크로 통일(초록/민트 금지).
                            '빠른 길보다,\n갈 수 있는 길',
                            style: TextStyle(
                              color: EasySubwayAccessibleColors.text,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              height: 1.16,
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
                              backgroundColor:
                                  EasySubwayAccessibleColors.primary,
                              foregroundColor:
                                  EasySubwayAccessibleColors.surface,
                              minimumSize: const Size.fromHeight(58),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  EasySubwayRadius.control,
                                ),
                              ),
                            ),
                            child: const Text('시작하기'),
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
        borderRadius: BorderRadius.circular(EasySubwayRadius.sheet),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class _IntroDivider extends StatelessWidget {
  const _IntroDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 13),
      child: Divider(height: 1, color: EasySubwayAccessibleColors.line),
    );
  }
}

/// 진행 인디케이터 — 아주 작은 점 2개(애플식). 블록/박스 아님(#1936).
class _OnboardingStepDots extends StatelessWidget {
  const _OnboardingStepDots({
    required this.currentStep,
    required this.totalSteps,
  });

  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var step = 1; step <= totalSteps; step++) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: step <= currentStep
                    ? EasySubwayAccessibleColors.primary
                    : EasySubwayAccessibleColors.line,
              ),
              child: const SizedBox(width: 7, height: 7),
            ),
            if (step != totalSteps) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _PermissionInfoCard extends StatelessWidget {
  const _PermissionInfoCard({
    required this.locationSelected,
    required this.notificationSelected,
    required this.onLocationChanged,
    required this.onNotificationChanged,
    required this.notificationAvailable,
  });

  final bool locationSelected;
  final bool notificationSelected;
  final ValueChanged<bool> onLocationChanged;
  final ValueChanged<bool> onNotificationChanged;
  // 알림 기능이 이 빌드에서 제공되지 않으면 켜라고 요청하지 않는다(#1579).
  final bool notificationAvailable;

  @override
  Widget build(BuildContext context) {
    return _IntroCard(
      child: Column(
        children: [
          _PermissionInfoRow(
            icon: Icons.location_on_outlined,
            title: '현재 위치',
            subtitle: '가까운 역 찾기',
            value: locationSelected,
            onChanged: onLocationChanged,
          ),
          if (notificationAvailable) ...[
            const _IntroDivider(),
            _PermissionInfoRow(
              icon: Icons.notifications_none,
              title: '알림',
              subtitle: '시설 고장·복구 알림',
              value: notificationSelected,
              onChanged: onNotificationChanged,
            ),
          ],
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 43,
          height: 43,
          child: Icon(
            icon,
            color: EasySubwayAccessibleColors.primary,
            size: 26,
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
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: EasySubwayAccessibleColors.mutedText,
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
              activeTrackColor: EasySubwayAccessibleColors.switchActiveTrack,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor:
                  EasySubwayAccessibleColors.switchInactiveTrack,
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
  // #1936: 첫 프리셋을 기본 선택으로 두어 "이대로 시작"으로 빠르게 통과할 수 있게 한다.
  MobilityProfileOption? _selectedProfile = mobilityProfileOptions.first;
  // 온보딩에서는 보기 설정(고대비·간편 보기)을 다루지 않는다. 기본값으로 완료하고,
  // 상세 설정은 더보기·설정 화면에서 바꾼다(#1563).
  final OnboardingViewPreferences _preferences =
      const OnboardingViewPreferences.defaults();
  int _currentStep = 0;
  bool _locationPermissionSelected = false;
  bool _notificationPermissionSelected = false;
  bool _showNotificationPermissionFailureNextAction = false;

  @override
  Widget build(BuildContext context) {
    final selectedProfile = _selectedProfile;
    final textTheme = Theme.of(context).textTheme;
    // 알림 기능 가용 여부의 단일 소스: 알림 권한 provider가 주입됐는지(#1579).
    // 더보기 알림 섹션(notificationRepository)과 함께 켜지고 꺼진다.
    final notificationAvailable = widget.notificationPermissionProvider != null;
    final listBottomPadding = _currentStep == 1 ? 32.0 : 104.0;
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
      bottomNavigationBar: _currentStep == 1
          ? null
          : Padding(
              padding: easySubwayBottomActionInsets(context, top: 8),
              child: FilledButton(
                key: const Key('onboardingDoneButton'),
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: EasySubwayAccessibleColors.primary,
                  foregroundColor: EasySubwayAccessibleColors.surface,
                  minimumSize: const Size.fromHeight(58),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      EasySubwayRadius.control,
                    ),
                  ),
                ),
                // #1936: 기본 선택으로 빠르게 통과하는 프리셋 화면의 CTA.
                child: const Text('이대로 시작'),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            EasySubwaySpacing.xl,
            EasySubwaySpacing.lg,
            EasySubwaySpacing.xl,
            listBottomPadding,
          ),
          children: _currentStep == 0
              ? [
                  const _OnboardingStepDots(currentStep: 1, totalSteps: 2),
                  const SizedBox(height: EasySubwaySpacing.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      // 질문 한 줄, 설명 문장 없음(#1936).
                      '어떻게 이동하세요?',
                      style: textTheme.titleLarge?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: EasySubwaySpacing.xl),
                  for (var i = 0; i < profileOptions.length; i++) ...[
                    if (i != 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: EasySubwayAccessibleColors.line,
                      ),
                    _OnboardingProfileRow(
                      profile: profileOptions[i],
                      selected: profileOptions[i].id == selectedProfile?.id,
                      onTap: () {
                        setState(() {
                          _selectedProfile = profileOptions[i];
                        });
                      },
                    ),
                  ],
                ]
              : [
                  const _OnboardingStepDots(currentStep: 2, totalSteps: 2),
                  const SizedBox(height: EasySubwaySpacing.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      notificationAvailable
                          ? '위치와 알림은 나중에도 켤 수 있어요'
                          : '위치는 나중에도 켤 수 있어요',
                      style: textTheme.headlineSmall?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w800,
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
                    notificationAvailable: notificationAvailable,
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
                          color: EasySubwayAccessibleColors.mutedText,
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
                    child: const Text('시작하기'),
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

/// #1936: 이동 방식 프리셋 행 — 라벨만. 박스 아님(행 + Divider는 부모가 그림).
/// 설명 문장 없음, 아이콘 없음. 선택 시 우측에 체크 표시. 탭 스플래시 사각형이
/// 생기지 않도록 GestureDetector를 쓰고, 높이는 접근성 터치 기준(≥56)을 지킨다.
class _OnboardingProfileRow extends StatelessWidget {
  const _OnboardingProfileRow({
    required this.profile,
    required this.selected,
    required this.onTap,
  });

  final MobilityProfileOption profile;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: profile.semanticsLabel(selected),
      selected: selected,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: Key('onboardingProfileCard-${profile.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      // 라벨만 노출한다. 상세 요약은 홈 설정에서 확인(#1936).
                      profile.title,
                      style: textTheme.bodyLarge?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                        fontSize: 18,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(width: EasySubwaySpacing.md),
                  if (selected)
                    const Icon(
                      Icons.check,
                      size: 22,
                      color: EasySubwayAccessibleColors.primary,
                    )
                  else
                    const SizedBox(width: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
