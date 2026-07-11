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

/// 화면 1 — 시작. 상단 브랜드 심볼(무채색 라인) + 핵심 가치 큰 타이틀 + 단일 CTA.
///
/// #1936(프리미엄 다듬기): 텍스트+버튼만이라 밋밋하다는 판정에 대응해, 상단에
/// 무채색 라인 아트 브랜드 심볼/워드마크를 둔다. 색·그림자·블록 없이 심볼만으로
/// 브랜딩을 세우고, 심볼–타이틀–여백–CTA의 세로 리듬을 균형 있게 구성한다.
/// 상단 여백을 크게 비운 뒤 심볼→타이틀, Spacer로 CTA를 하단에 고정한다.
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
            // 상단 여백을 비워 심볼이 화면 상단 1/4 지점에서 시작하게 한다.
            // 이전(~35%)보다 살짝 줄여 심볼–타이틀 묶음이 화면 중앙 위로 앉는다.
            final topGap = (constraints.maxHeight * 0.22).clamp(64.0, 168.0);
            // SafeArea(bottom: true) 자손이라 하단 인셋은 SafeArea가 이미 적용한다.
            // viewPadding.bottom을 또 더하면 이중 가산이므로 토큰 여백만 쓴다.
            const bottomGap = EasySubwaySpacing.xxl;
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
                        // 브랜드 심볼(무채색 라인 아트) + 워드마크. 밋밋함 해소(#1936).
                        const _BrandMark(),
                        const SizedBox(height: EasySubwaySpacing.xxl),
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

/// #1936: 미니멀 무채색 브랜드 심볼 + 워드마크.
///
/// 심볼은 노선·경로를 은유하는 라인 아트(두 정거장을 잇는 route 글리프)로,
/// 색·그림자·블록 없이 잉크 라인과 점만으로 그린다. 워드마크는 앱 이름을
/// 무채색 잉크로 둔다(w800은 화면 타이틀 예산 밖으로 두어 w700 + 자간). 브랜드
/// 부재로 인한 "텍스트+버튼만" 밋밋함을 해소하는 시각 앵커다.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '쉬운 지하철',
      image: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size(40, 40),
              painter: _RouteGlyphPainter(
                color: EasySubwayAccessibleColors.text,
              ),
            ),
            const SizedBox(width: EasySubwaySpacing.md),
            Text(
              '쉬운 지하철',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: EasySubwayAccessibleColors.text,
                fontWeight: FontWeight.w700,
                fontSize: 19,
                letterSpacing: -0.2,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 노선/경로 글리프 — 두 정거장을 잇는 무채색 라인 아트.
///
/// 굵은 라인 1개 + 양끝 정거장 노드(속이 빈 원)로 "이동 경로"를 은유한다.
/// 색 없이 잉크 선만 쓰고, 그림자·채움 블록은 두지 않는다(#1936 제약).
class _RouteGlyphPainter extends CustomPainter {
  const _RouteGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.11;
    final cy = size.height * 0.5;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final nodeRadius = size.width * 0.17;
    final left = Offset(nodeRadius + stroke * 0.5, cy);
    final right = Offset(size.width - nodeRadius - stroke * 0.5, cy);

    // 두 정거장을 잇는 경로 라인.
    canvas.drawLine(
      Offset(left.dx + nodeRadius, cy),
      Offset(right.dx - nodeRadius, cy),
      line,
    );

    // 양끝 정거장 노드(속 빈 원 = 라인 아트).
    final node = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(left, nodeRadius, node);
    canvas.drawCircle(right, nodeRadius, node);
  }

  @override
  bool shouldRepaint(_RouteGlyphPainter oldDelegate) =>
      oldDelegate.color != color;
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

/// #1936: 이동 방식 프리셋 행 — 무채색 라인 아이콘 + 라벨 + 우측 선택 표시.
///
/// personalization-first 리스트로서 프리미엄 리듬을 위해 좌측에 무채색 라인
/// 아이콘을 둔다(색 없음 — 선택 여부와 무관하게 잉크 톤). 박스 아님(행 + Divider는
/// 부모가 그림). 설명 문장 없음. 선택 시 우측에 체크 표시. 탭 스플래시 사각형이
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
                  // 무채색 라인 아이콘 — 시각 리듬만. 선택 시 잉크를 진하게 해
                  // 색 없이도 선택 위계를 준다(초록/틴트 금지).
                  Icon(
                    profile.icon,
                    size: 24,
                    color: selected
                        ? EasySubwayAccessibleColors.text
                        : EasySubwayAccessibleColors.mutedText,
                  ),
                  const SizedBox(width: EasySubwaySpacing.lg),
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
