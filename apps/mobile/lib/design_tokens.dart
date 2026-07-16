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

/// 방사형 역 액션 메뉴(#2109) 전용 색. 오너 제작 SVG 원본 수치를 그대로
/// 옮긴 화면 로컬 톤이라 [EasySubwayTokens] 의미 토큰으로 수렴하지 않는다
/// (design_guard_test.dart 로컬 색 상수 ratchet 해소 경로).
abstract final class EasySubwayFanMenuColors {
  static const disabledOpacity = 0.40;
  static const pressedOpacity = 0.84;
  static const departure = Color(0xFF176FD1);
  static const departureSurface = Color(0xFFF7FAFF);
  static const departurePressed = Color(0xFFEAF3FF);
  static const waypoint = Color(0xFFBF5700);
  static const waypointSurface = Color(0xFFFFFAF4);
  static const waypointPressed = Color(0xFFFFF0DE);
  static const arrival = Color(0xFFD9252E);
  static const arrivalSurface = Color(0xFFFFF8F8);
  static const arrivalPressed = Color(0xFFFFECEE);
  static const closeSurface = Color(0xFFF5F7FA);
  static const closePressed = Color(0xFFE9EDF2);
  static const closeInk = Color(0xFF475467);
  // 세그먼트 사이 내부 구분선 색. QA 결과 외곽선과 옅기 차이를 두면 위계가
  // 흐릿해 보여, 외곽선(outline)과 동일 톤으로 통일한다(#2200 절충안, 오너
  // 확정 2026-07-17). 굵기 차이(structuralStrokeWidth vs dividerStrokeWidth,
  // station_fan_menu.dart 참고)로만 내부/외곽 위계를 만든다.
  static const border = Color(0xE8404445);
  // 팬 메뉴 도입 전(#2109/PR #2112) 사각형 역 액션 시트가 쓰던 외곽 색을 그대로
  // 계승한다(구 시트 Material color 0xE8404445, 오너 지시 2026-07-16).
  static const outline = Color(0xE8404445);

  /// 팬 메뉴 앵커 역명 라벨의 텍스트 잉크.
  static const ink = Color(0xFF20262E);
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
