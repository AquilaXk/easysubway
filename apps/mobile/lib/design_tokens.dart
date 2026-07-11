import 'package:flutter/material.dart';

import 'accessible_design.dart';

/// v4 간격 스케일. 박스 대신 여백이 그룹을 만든다 (#1915).
abstract final class EasySubwaySpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// v4 radius 스케일. 라운드는 떠 있는 표면(컨트롤·카드·시트)에만 쓴다.
abstract final class EasySubwayRadius {
  static const control = 8.0;
  static const card = 12.0;
  static const sheet = 16.0;
}

/// v4 의미 색 토큰. 라이트 값은 [EasySubwayAccessibleColors]를 원천으로 한다.
///
/// #1917(다크 모드)이 dark 인스턴스를 추가한다 — 필드를 늘릴 때는
/// 다크 대응 값을 함께 정의할 수 있는지 확인할 것.
@immutable
class EasySubwayTokens extends ThemeExtension<EasySubwayTokens> {
  const EasySubwayTokens({
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.line,
    required this.surface,
    required this.scaffold,
    required this.accent,
    required this.good,
    required this.warn,
    required this.danger,
    required this.mapSelectionAccent,
    required this.mapRegionAccent,
  });

  static const light = EasySubwayTokens(
    ink: EasySubwayAccessibleColors.text,
    inkSecondary: EasySubwayAccessibleColors.secondaryText,
    inkMuted: EasySubwayAccessibleColors.mutedText,
    line: EasySubwayAccessibleColors.line,
    surface: EasySubwayAccessibleColors.surface,
    scaffold: EasySubwayAccessibleColors.scaffoldSurface,
    accent: EasySubwayAccessibleColors.primary,
    good: EasySubwayAccessibleColors.mint,
    warn: EasySubwayAccessibleColors.amber,
    danger: EasySubwayAccessibleColors.red,
    // 지도 오버레이 전용 — 지도 배경 시인성 때문에 accent로 수렴하지 않는다
    // (network_map의 기존 설계 의도 승계).
    mapSelectionAccent: EasySubwayAccessibleColors.mapSelectionAccent,
    mapRegionAccent: EasySubwayAccessibleColors.mapRegionAccent,
  );

  /// #1917 다크 세트. 명도 위계는 라이트를 반전하되 채도를 낮춰 눈부심을 줄인다.
  /// 지도 오버레이 선택 톤은 다크 지도 배경에서도 동일 시인성이라 유지한다.
  ///
  /// 주의: 화면들이 아직 정적 팔레트(EasySubwayAccessibleColors)를 직접 참조하는
  /// 동안에는 시스템 추종(ThemeMode.system)을 켜지 않는다 — 혼합 렌더링(밝은
  /// 위젯 + 어두운 배경)이 생기기 때문. 전환 조건은 #1917 참조.
  static const dark = EasySubwayTokens(
    ink: Color(0xFFE6EDEE),
    inkSecondary: Color(0xFFB8C7C9),
    inkMuted: Color(0xFF8FA5A8),
    line: Color(0xFF2A3B3D),
    surface: Color(0xFF162223),
    scaffold: Color(0xFF0F1A1B),
    accent: Color(0xFFD6DADC),
    good: Color(0xFF5BC8A8),
    warn: Color(0xFFE0A54E),
    danger: Color(0xFFF28B82),
    mapSelectionAccent: EasySubwayAccessibleColors.mapSelectionAccent,
    mapRegionAccent: Color(0xFF4D9FE8),
  );

  /// 본문 텍스트.
  final Color ink;

  /// 보조 텍스트.
  final Color inkSecondary;

  /// 흐린 텍스트·비활성.
  final Color inkMuted;

  /// 구분선·얇은 테두리.
  final Color line;

  /// 기본 표면.
  final Color surface;

  /// 스캐폴드 배경.
  final Color scaffold;

  /// 브랜드 액센트 — CTA·선택 상태·링크에만 쓴다.
  final Color accent;

  /// 정상·복구 상태 (아이콘+텍스트에만, 배경 틴트 금지).
  final Color good;

  /// 주의 상태 (아이콘+텍스트에만, 배경 틴트 금지).
  final Color warn;

  /// 고장·오류 상태 (아이콘+텍스트에만, 배경 틴트 금지).
  final Color danger;

  /// 지도 위 선택 역 말풍선 톤.
  final Color mapSelectionAccent;

  /// 지도 위 지역 선택 칩 톤.
  final Color mapRegionAccent;

  static EasySubwayTokens of(BuildContext context) =>
      Theme.of(context).extension<EasySubwayTokens>() ?? light;

  @override
  EasySubwayTokens copyWith({
    Color? ink,
    Color? inkSecondary,
    Color? inkMuted,
    Color? line,
    Color? surface,
    Color? scaffold,
    Color? accent,
    Color? good,
    Color? warn,
    Color? danger,
    Color? mapSelectionAccent,
    Color? mapRegionAccent,
  }) {
    return EasySubwayTokens(
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      line: line ?? this.line,
      surface: surface ?? this.surface,
      scaffold: scaffold ?? this.scaffold,
      accent: accent ?? this.accent,
      good: good ?? this.good,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      mapSelectionAccent: mapSelectionAccent ?? this.mapSelectionAccent,
      mapRegionAccent: mapRegionAccent ?? this.mapRegionAccent,
    );
  }

  @override
  EasySubwayTokens lerp(EasySubwayTokens? other, double t) {
    if (other == null) {
      return this;
    }
    Color lerpColor(Color a, Color b) => Color.lerp(a, b, t)!;
    return EasySubwayTokens(
      ink: lerpColor(ink, other.ink),
      inkSecondary: lerpColor(inkSecondary, other.inkSecondary),
      inkMuted: lerpColor(inkMuted, other.inkMuted),
      line: lerpColor(line, other.line),
      surface: lerpColor(surface, other.surface),
      scaffold: lerpColor(scaffold, other.scaffold),
      accent: lerpColor(accent, other.accent),
      good: lerpColor(good, other.good),
      warn: lerpColor(warn, other.warn),
      danger: lerpColor(danger, other.danger),
      mapSelectionAccent: lerpColor(
        mapSelectionAccent,
        other.mapSelectionAccent,
      ),
      mapRegionAccent: lerpColor(mapRegionAccent, other.mapRegionAccent),
    );
  }
}

/// v4 타이포 위계 — 크기·행간·색으로 위계를 만들고 굵기는 보조로만 쓴다.
///
/// w800+는 화면 타이틀(titleLarge) 한정, 본문 w500, 라벨 w600, 행 강조 w700.
TextTheme easySubwayTextTheme(TextTheme base) {
  return base.copyWith(
    titleLarge: base.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.25,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.3,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
}

/// v4 공유 테마 빌더 — 라이트/다크가 동일한 컴포넌트 테마(앱바·버튼)를 쓰도록
/// 토큰에서 ThemeData를 조립한다. 라이트 경로는 기존 main.dart 인라인 빌더와
/// 완전 동치여야 한다(위젯 테스트가 증거).
ThemeData easySubwayThemeFromTokens(
  EasySubwayTokens tokens, {
  required Brightness brightness,
}) {
  final base = ThemeData(
    // fromSeed는 시드의 미세한 hue를 M3 톤 팔레트로 증폭해 액센트를 채도
    // 있는 색으로 만든다(무채색 시드도 청록끼로 샌다). 무채색 잉크 원칙을
    // 지키려 primary/secondary 계열을 명시적 무채색으로 덮어쓴다.
    colorScheme: brightness == Brightness.dark
        ? ColorScheme.fromSeed(
            seedColor: EasySubwayAccessibleColors.primary,
            brightness: Brightness.dark,
          )
        : ColorScheme.fromSeed(
            seedColor: EasySubwayAccessibleColors.primary,
          ),
    useMaterial3: true,
  );
  // 라이트: 밝은 액센트 위 흰 잉크(현행 유지). 다크: 밝은 액센트 위 어두운
  // 잉크(tokens.scaffold=#0F1A1B)로 대비 확보(흰 잉크는 대비 실패).
  final onAccent = brightness == Brightness.dark ? tokens.scaffold : Colors.white;
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      primary: tokens.accent,
      onPrimary: onAccent,
      secondary: tokens.accent,
      onSecondary: onAccent,
    ),
    extensions: [tokens],
    scaffoldBackgroundColor: tokens.scaffold,
    textTheme: easySubwayTextTheme(base.textTheme),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      toolbarHeight: 64,
      // 평평한 상단바: Material3 surfaceTint(액센트 기반 청록 스크림)와
      // 스크롤 elevation 그림자를 끈다. 경계는 화면별 얇은 구분선으로만.
      backgroundColor: tokens.scaffold,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: tokens.ink,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
    ),
    // 주 행동(채움)만 강하게: 높이 60, 진한 채움.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(EasySubwayTouchTarget.primary),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(EasySubwayRadius.card)),
        ),
        textStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    // 보조 행동은 조용하게: 중립 얇은 보더(line 토큰) + accent 텍스트,
    // 높이는 접근성 최소(56).
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(EasySubwayTouchTarget.general),
        foregroundColor: tokens.accent,
        side: BorderSide(
          color: tokens.line,
          width: 1.5,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(EasySubwayRadius.card)),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

/// #1917 다크 테마 기반. 시스템 추종 전환 전까지 darkTheme 등록만 해 둔다.
ThemeData easySubwayDarkTheme() {
  return easySubwayThemeFromTokens(
    EasySubwayTokens.dark,
    brightness: Brightness.dark,
  );
}
