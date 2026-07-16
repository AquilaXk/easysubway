import 'dart:convert';

import 'package:flutter/material.dart';

import 'accessible_design.dart';
import 'design_tokens.dart';
import 'features/mobility_profile/mobility_preset_labels.dart';
import 'features/mobility_profile/mobility_preset_picker.dart'
    show MobilityPresetRow, mobilityPresetSheetOrder;
import 'features/mobility_profile/mobility_profile_policy.dart';
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
  const OnboardingResult({required this.preset, required this.preferences});

  factory OnboardingResult.fromJson(Map<String, Object?> json) {
    final preferences = json['preferences'];
    if (preferences is! Map<String, Object?>) {
      throw const FormatException('Invalid onboarding storage payload');
    }

    final preset = _readPreset(json);
    if (preset == null) {
      throw const FormatException('Invalid onboarding preset');
    }

    return OnboardingResult(
      preset: preset,
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

  final MobilityPreset preset;
  final OnboardingViewPreferences preferences;

  /// 프리셋 대표 이동 유형 문자열(요청·설정에 공급).
  String get mobilityType => mobilityPresetRepresentativeMobilityType(preset);

  Map<String, Object?> toJson() {
    return {
      'preset': mobilityPresetServerString(preset),
      'preferences': preferences.toJson(),
    };
  }

  String encode() {
    return jsonEncode(toJson());
  }

  /// 신규 `preset`(server string) 우선, 없으면 구 `profileId`를 승계한다(데이터 소실 금지).
  static MobilityPreset? _readPreset(Map<String, Object?> json) {
    final preset = json['preset'];
    if (preset is String) {
      return mobilityPresetFromServerString(preset);
    }
    final profileId = json['profileId'];
    if (profileId is String) {
      return mobilityPresetFromLegacyProfileId(profileId);
    }
    return null;
  }
}

class OnboardingState {
  const OnboardingState.initial() : result = null;

  const OnboardingState.completed({required this.result});

  final OnboardingResult? result;

  bool get isCompleted => result != null;
}

/// 화면 1 — 시작. 핵심 가치 카피 3행 + 단일 CTA만 둔 카피 중심 화면.
///
/// #2081: 상단 브랜드 심볼/워드마크를 걷어내고 카피만으로 화면을 세운다.
/// 가치 카피 3행을 크게 두고 Spacer로 CTA를 하단에 고정하며, 상단 여백을 비워
/// 타이틀이 화면 상단 1/4~1/3 지점에서 시작하는 세로 리듬을 유지한다.
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
            // 상단 여백을 비워 타이틀이 화면 상단 1/4~1/3 지점에서 시작하게 한다.
            // 심볼 제거(#2081)로 세로 여백을 조금 넉넉히 잡아 타이틀 묶음을 앉힌다.
            final topGap = (constraints.maxHeight * 0.28).clamp(72.0, 200.0);
            // SafeArea(bottom: true) 자손이라 하단 인셋은 SafeArea가 이미 적용한다.
            // viewPadding.bottom을 또 더하면 이중 가산이므로 토큰 여백만 쓴다.
            // #2089(오너 실기기 검수): CTA가 화면 최하단에 과하게 붙어 있어
            // 하단 여백을 xxl의 2배로 늘려 버튼을 세로 리듬 안에서 위로 올린다.
            const bottomGap = EasySubwaySpacing.xxl * 2;
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
                          child: Text.rich(
                            // 핵심 가치 카피 3행(#2081). #2089: 2행 중 "갈 수 있는
                            // 길"까지만 시그니처 브랜드 색으로 강조하고, 조사 "을"과
                            // 1·3행은 기존 잉크 토큰을 유지한다(오너 실기기 검수).
                            // 스크린리더가 읽는 전체 문자열은 그대로 보존된다.
                            const TextSpan(
                              children: [
                                TextSpan(text: '빠른 길보다\n'),
                                TextSpan(
                                  text: '갈 수 있는 길',
                                  style: TextStyle(
                                    color: EasySubwayAccessibleColors
                                        .brandSignature,
                                  ),
                                ),
                                TextSpan(text: '을\n안내합니다'),
                              ],
                            ),
                            style: const TextStyle(
                              color: EasySubwayAccessibleColors.text,
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              height: 1.18,
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
                              // #2089: 시작 CTA만 시그니처 브랜드 색 채움 +
                              // 흰 글자(대비 5.7:1, AA 통과).
                              backgroundColor:
                                  EasySubwayAccessibleColors.brandSignature,
                              foregroundColor:
                                  EasySubwayAccessibleColors.surface,
                              minimumSize: const Size.fromHeight(58),
                              // #2089(오너 실기기 검수 2차): 58px 버튼 대비 라벨이
                              // 여전히 작아 보여 글자를 더 키운다(22/w700, 가독 우선).
                              textStyle: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
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

/// #1936(전체 워크플로우 일관성): 권한 항목 목록 — 박스(Card) 금지 → 행 + Divider.
///
/// 프로필 프리셋 리스트와 같은 디자인 언어(무채색 라인 아이콘 + 라벨 + 짧은 한 줄)
/// 를 쓰되, 우측은 켜기 스위치다. DecoratedBox/Border(박스) 없이 행과 구분선만으로
/// 그룹을 만든다.
class _PermissionInfoList extends StatelessWidget {
  const _PermissionInfoList({
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
    return Column(
      children: [
        _PermissionInfoRow(
          icon: Icons.location_on_outlined,
          title: '현재 위치',
          subtitle: '가까운 역 찾기',
          value: locationSelected,
          onChanged: onLocationChanged,
        ),
        if (notificationAvailable) ...[
          const Divider(
            height: 1,
            thickness: 1,
            color: EasySubwayAccessibleColors.line,
          ),
          _PermissionInfoRow(
            icon: Icons.notifications_none,
            title: '알림',
            subtitle: '시설 고장·복구 알림',
            value: notificationSelected,
            onChanged: onNotificationChanged,
          ),
        ],
      ],
    );
  }
}

/// 권한 행 — 무채색 라인 아이콘 + 라벨 + 짧은 한 줄 + 우측 켜기 스위치.
///
/// 프로필 프리셋 행과 같은 톤: 좌측 아이콘은 잉크(무채색), 라벨은 bodyLarge,
/// 보조 한 줄은 mutedText. 박스 없음, 높이는 접근성 터치 기준(≥56)을 지킨다.
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
    final textTheme = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            // 무채색 라인 아이콘 — 프로필 리스트와 같은 시각 리듬(색 없음).
            Icon(icon, color: EasySubwayAccessibleColors.mutedText, size: 24),
            const SizedBox(width: EasySubwaySpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: textTheme.bodyLarge?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodyMedium?.copyWith(
                      color: EasySubwayAccessibleColors.mutedText,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: EasySubwaySpacing.md),
            Semantics(
              label: '$title ${value ? '켜짐' : '꺼짐'}',
              toggled: value,
              onTap: () => onChanged(!value),
              child: ExcludeSemantics(
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: Colors.white,
                  activeTrackColor:
                      EasySubwayAccessibleColors.switchActiveTrack,
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor:
                      EasySubwayAccessibleColors.switchInactiveTrack,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
            ),
          ],
        ),
      ),
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
  // #1936: 기본 선택(표준 보행)을 두어 "이대로 시작"으로 빠르게 통과할 수 있게 한다.
  MobilityPreset _selectedPreset = MobilityPreset.standard;
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
    final textTheme = Theme.of(context).textTheme;
    // 알림 기능 가용 여부의 단일 소스: 알림 권한 provider가 주입됐는지(#1579).
    // 더보기 알림 섹션(notificationRepository)과 함께 켜지고 꺼진다.
    final notificationAvailable = widget.notificationPermissionProvider != null;

    // 프리셋은 항상 기본값이 선택돼 있어 CTA는 늘 활성이다(#1703).
    void onNext() {
      if (_currentStep == 0) {
        setState(() => _currentStep = 1);
        return;
      }
      _completeOnboarding();
    }

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
        child: _currentStep == 0
            ? ListView(
                padding: const EdgeInsets.fromLTRB(
                  EasySubwaySpacing.xl,
                  EasySubwaySpacing.lg,
                  EasySubwaySpacing.xl,
                  104,
                ),
                children: [
                  const _OnboardingStepDots(currentStep: 1, totalSteps: 2),
                  const SizedBox(height: EasySubwaySpacing.xl),
                  Semantics(
                    header: true,
                    child: Text(
                      // 질문 한 줄, 설명 문장 없음(#1936).
                      '어떻게 걸으세요?',
                      style: textTheme.titleLarge?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: EasySubwaySpacing.xl),
                  for (var i = 0; i < mobilityPresetSheetOrder.length; i++) ...[
                    if (i != 0)
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: EasySubwayAccessibleColors.line,
                      ),
                    MobilityPresetRow(
                      preset: mobilityPresetSheetOrder[i],
                      selected: mobilityPresetSheetOrder[i] == _selectedPreset,
                      // 온보딩 step0은 각 행 아래 부가설명도 노출한다(#1703).
                      showDescription: true,
                      onTap: () {
                        setState(() {
                          _selectedPreset = mobilityPresetSheetOrder[i];
                        });
                      },
                    ),
                  ],
                ],
              )
            // #1936(원칙 #1933): 시작 화면과 같은 리듬 — 콘텐츠 위, CTA는 Spacer로
            // 하단 고정. 큰 글씨/작은 화면에서도 스크롤 가능하게 LayoutBuilder +
            // SingleChildScrollView + ConstrainedBox(minHeight) + IntrinsicHeight를 쓴다.
            : LayoutBuilder(
                builder: (context, constraints) {
                  // SafeArea(bottom: true) 자손이라 하단 인셋은 SafeArea가 이미 적용한다.
                  // viewPadding.bottom을 또 더하면 이중 가산이므로 토큰 여백만 쓴다.
                  const bottomGap = EasySubwaySpacing.xxl;
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            EasySubwaySpacing.xl,
                            EasySubwaySpacing.lg,
                            EasySubwaySpacing.xl,
                            bottomGap,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _OnboardingStepDots(
                                currentStep: 2,
                                totalSteps: 2,
                              ),
                              const SizedBox(height: EasySubwaySpacing.xl),
                              Semantics(
                                header: true,
                                child: Text(
                                  notificationAvailable
                                      ? '위치와 알림은 나중에도 켤 수 있어요'
                                      : '위치는 나중에도 켤 수 있어요',
                                  // 프로필 질문과 같은 타이포 위계(titleLarge)로 통일(#1936 일관성).
                                  style: textTheme.titleLarge?.copyWith(
                                    color: EasySubwayAccessibleColors.text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 26,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: EasySubwaySpacing.xl),
                              _PermissionInfoList(
                                locationSelected: _locationPermissionSelected,
                                notificationSelected:
                                    _notificationPermissionSelected,
                                onLocationChanged: (value) => setState(
                                  () => _locationPermissionSelected = value,
                                ),
                                onNotificationChanged: (value) => setState(
                                  () => _notificationPermissionSelected = value,
                                ),
                                notificationAvailable: notificationAvailable,
                              ),
                              if (_showNotificationPermissionFailureNextAction) ...[
                                const SizedBox(height: 12),
                                Semantics(
                                  key: const Key(
                                    'onboardingNotificationFailureNextAction',
                                  ),
                                  container: true,
                                  excludeSemantics: true,
                                  liveRegion: true,
                                  label:
                                      '도움말, $_onboardingNotificationFailureNextAction',
                                  child: Text(
                                    _onboardingNotificationFailureNextAction,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color:
                                          EasySubwayAccessibleColors.mutedText,
                                      fontWeight: FontWeight.w700,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              const SizedBox(height: EasySubwaySpacing.xl),
                              FilledButton(
                                key: const Key(
                                  'onboardingPermissionAllowButton',
                                ),
                                onPressed:
                                    _locationPermissionSelected ||
                                        _notificationPermissionSelected
                                    ? _handlePermissionAllow
                                    : null,
                                style: FilledButton.styleFrom(
                                  // 시작·프로필 CTA와 같은 무채색 잉크 fill + 각진(≤8)로 통일.
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
                              const SizedBox(height: EasySubwaySpacing.sm),
                              OutlinedButton(
                                key: const Key(
                                  'onboardingPermissionSkipButton',
                                ),
                                onPressed: _completeOnboarding,
                                style: OutlinedButton.styleFrom(
                                  // "나중에" skip — 무채색 잉크 텍스트 + 얇은 라인 테두리(각진).
                                  foregroundColor:
                                      EasySubwayAccessibleColors.text,
                                  side: const BorderSide(
                                    color: EasySubwayAccessibleColors.line,
                                  ),
                                  minimumSize: const Size.fromHeight(58),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      EasySubwayRadius.control,
                                    ),
                                  ),
                                ),
                                child: const Text('나중에 설정'),
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

  void _goBack() {
    if (_currentStep == 0) {
      return;
    }
    setState(() => _currentStep -= 1);
  }

  void _completeOnboarding() {
    widget.onCompleted(
      OnboardingResult(preset: _selectedPreset, preferences: _preferences),
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
