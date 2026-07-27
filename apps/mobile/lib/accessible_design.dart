import 'dart:ui' as ui;

import 'package:flutter/material.dart';

abstract final class EasySubwayColorPrimitives {
  static const brand50 = Color(0xFFF8F9FF);
  static const brand100 = Color(0xFFF0F2FE);
  static const brand200 = Color(0xFFE2E5FD);
  static const brand300 = Color(0xFFCCD2FC);
  static const brand400 = Color(0xFFB4BCFB);
  static const brand500 = Color(0xFF949FE8);
  static const brand600 = Color(0xFF7480D2);
  static const brand700 = Color(0xFF5C6BC0);
  static const brand800 = Color(0xFF4A58A9);
  static const brand900 = Color(0xFF3B4890);
  static const brand950 = Color(0xFF1F2340);
  static const neutralWhite = Color(0xFFFFFFFF);
  static const neutralScaffold = Color(0xFFF7F8FC);
  static const neutralSubtle = Color(0xFFF0F2F7);
  static const neutralBorder = Color(0xFFE1E4EE);
  static const inkSecondary = Color(0xFF4D536B);
  static const inkMuted = Color(0xFF697089);
  static const statusSuccess = Color(0xFF0A705A);
  static const statusWarning = Color(0xFF9A5600);
  static const statusDanger = Color(0xFFB42318);
  static const statusInfo = Color(0xFF215EA8);
  static const statusSuccessSoft = Color(0xFFF0FBF7);
  static const statusWarningSoft = Color(0xFFFFF0D1);
  static const statusDangerSoft = Color(0xFFFFE8E6);
  static const statusInfoSoft = Color(0xFFEEF5FF);
}

/// 노선도 화면을 기준으로 삼는 앱 공용 색 팔레트.
///
/// 역할별로 상수를 묶어 화면마다 색이 섞이지 않게 한다.
/// - 브랜드 액센트는 [primary] 1계열만 사용한다. 과거 navy 액센트([brand])는
///   이 액센트로 통일했다.
/// - 상태색(정상/주의/고장)은 의미가 있는 곳에만 쓴다.
/// - soft 틴트 배경은 상태 표현용이며 장식용으로 쓰지 않는다.
///
/// 타이포 위계 가이드(전 화면 공통):
/// - 본문·라벨: w500~w600
/// - 강조(행 타이틀·값): w700~w800
/// - 화면 타이틀만 w800 이상(w900은 화면 타이틀에 한정)
class EasySubwayAccessibleColors {
  const EasySubwayAccessibleColors._();

  static const surfaceDefault = EasySubwayColorPrimitives.neutralWhite;
  static const surfaceScaffold = EasySubwayColorPrimitives.neutralScaffold;
  static const surfaceSubtle = EasySubwayColorPrimitives.neutralSubtle;
  static const surfaceBrandChrome = EasySubwayColorPrimitives.brand50;
  static const surfaceBrand = EasySubwayColorPrimitives.brand100;
  static const surfaceBrandStrong = EasySubwayColorPrimitives.brand200;
  static const surfaceSignature = EasySubwayColorPrimitives.brand400;
  static const borderSubtle = EasySubwayColorPrimitives.neutralBorder;
  static const contentPrimary = EasySubwayColorPrimitives.brand950;
  static const contentSecondary = EasySubwayColorPrimitives.inkSecondary;
  static const contentMuted = EasySubwayColorPrimitives.inkMuted;
  static const interactionPrimary = EasySubwayColorPrimitives.brand700;
  static const interactionPrimaryPressed = EasySubwayColorPrimitives.brand800;
  static const interactionOnPrimary = EasySubwayColorPrimitives.neutralWhite;
  static const interactionSecondarySurface = EasySubwayColorPrimitives.brand100;
  static const interactionSecondaryBorder = EasySubwayColorPrimitives.brand600;
  static const interactionSecondaryPressedSurface =
      EasySubwayColorPrimitives.brand200;
  static const interactionSecondaryPressedBorder =
      EasySubwayColorPrimitives.brand700;
  static const interactionOnSignatureBorder =
      EasySubwayColorPrimitives.brand900;
  static const interactionOnBrand = EasySubwayColorPrimitives.brand900;
  static const focusDefault = EasySubwayColorPrimitives.brand700;
  static const focusOnSignature = EasySubwayColorPrimitives.brand900;
  static const decorativeDivider = EasySubwayColorPrimitives.brand300;
  static const statusSuccessContent = EasySubwayColorPrimitives.statusSuccess;
  static const statusSuccessSurface =
      EasySubwayColorPrimitives.statusSuccessSoft;
  static const statusWarningContent = EasySubwayColorPrimitives.statusWarning;
  static const statusWarningSurface =
      EasySubwayColorPrimitives.statusWarningSoft;
  static const statusDangerContent = EasySubwayColorPrimitives.statusDanger;
  static const statusDangerSurface = EasySubwayColorPrimitives.statusDangerSoft;
  static const statusInfoContent = EasySubwayColorPrimitives.statusInfo;
  static const statusInfoSurface = EasySubwayColorPrimitives.statusInfoSoft;

  static const surface = surfaceDefault;
  static const text = contentPrimary;
  static const secondaryText = contentSecondary;
  static const mutedText = contentMuted;
  static const line = borderSubtle;
  static const primary = interactionPrimary;
  static const brand = interactionPrimary;
  static const brandSignature = interactionPrimary;
  static const brandSignatureMedium = interactionSecondaryBorder;
  static const brandSignatureSoft = surfaceBrandStrong;
  static const brandSignatureSurface = surfaceSignature;
  static const topBarSurface = surfaceBrandChrome;
  static const searchFieldSurface = surfaceSubtle;
  static const needsInfo = statusInfoContent;
  static const skySoft = statusInfoSurface;
  static const scaffoldSurface = surfaceScaffold;

  /// 목록 행 라벨 (기준 화면 좌측 메뉴의 행 텍스트 톤).
  static const listRowText = contentPrimary;

  /// 섹션 캡션·부제 (기준 화면 좌측 메뉴의 섹션 톤).
  static const caption = contentMuted;

  /// 보조 아이콘 (기준 화면 검색바 아이콘 톤).
  static const iconMuted = contentMuted;

  /// 셰브런·디스클로저·비활성 아이콘.
  static const disclosure = contentMuted;

  /// 다크 히어로 등 짙은 브랜드 표면(레거시). 신규 화면에서는 사용하지 않는다.
  static const brandDark = contentPrimary;

  // --- 상태색: 정상/복구 (success) ---
  /// 정상·복구 상태 텍스트/아이콘.
  static const mint = statusSuccessContent;

  /// 정상·복구 상태 강조.
  static const mintDark = statusSuccessContent;

  /// 정상·복구 상태 배경 틴트.
  static const mintSoft = statusSuccessSurface;

  /// 정상·복구 상태 테두리.
  static const mintBorder = statusSuccessContent;

  // --- 상태색: 주의 (warning) ---
  /// 주의 상태 텍스트/아이콘.
  static const amber = statusWarningContent;

  /// 주의 상태 배경 틴트.
  static const amberSoft = statusWarningSurface;

  /// 주의 상태 테두리.
  static const amberBorder = statusWarningContent;

  // --- 상태색: 고장·오류 (danger) ---
  /// 고장·오류 상태 텍스트/아이콘.
  static const red = statusDangerContent;

  /// 고장·오류 상태 배경 틴트.
  static const redSoft = statusDangerSurface;

  /// 카드 그림자(최소 그림자 원칙).
  static const cardShadow = Color(0x0A071B2F);

  /// 스위치 켜짐 트랙.
  static const switchActiveTrack = brandSignature;

  /// 스위치 꺼짐 트랙.
  static const switchInactiveTrack = borderSubtle;

  // --- 지도 오버레이 전용 ---
  // 지도 배경 시인성 때문에 브랜드 액센트로 수렴하지 않는다 (기준 화면 실측 값).

  /// 지도 위 선택 역 말풍선 톤(밝은 시안).
  static const mapSelectionAccent = Color(0xFF007C91);

  /// 지도 위 지역 선택 칩 톤(밝은 블루).
  static const mapRegionAccent = Color(0xFF006FD6);

  // --- 홈 신규 알림 안내 바 (오너 스펙 2026-07-16, #2200) ---
  /// 신규 알림 안내 바 배경.
  static const noticeBarSurface = statusWarningSurface;

  /// 신규 알림 안내 바 하단 테두리(1dp).
  static const noticeBarBorder = statusWarningContent;

  /// 신규 알림 안내 바 기본 문구.
  static const noticeBarText = statusWarningContent;

  /// 신규 알림 안내 바 벨 아이콘·"알림 보기".
  static const noticeBarAccent = statusWarningContent;

  // --- 주변역 패널 실시간/시간표 토글 (오너 스펙 2026-07-16, #2200) ---
  /// 토글 비선택 세그먼트 배경.
  static const nearbyToggleIdleFill = surfaceSubtle;

  /// 토글 비선택 세그먼트 글자.
  static const nearbyToggleIdleText = contentSecondary;

  /// 좌우 열차 정보 구분선.
  static const arrivalColumnDivider = borderSubtle;

  // --- 고대비 모드 ---
  static const highContrastText = Color(0xFF000000);
  static const highContrastPrimary = Color(0xFF1A1D1E);
  static const highContrastSecondary = Color(0xFF3A4143);
}

class EasySubwayTouchTarget {
  const EasySubwayTouchTarget._();

  static const iconOnly = 48.0;
  static const general = 56.0;
  static const primary = 60.0;
}

/// 홈 노선도·역 검색 상단바 콘텐츠 높이(SafeArea/상태바 제외).
///
/// 두 화면은 왼쪽 아이콘(메뉴/뒤로)만 다르고 패딩·검색 필드·지역·구분선
/// 계약을 공유한다. 이 상수를 바꾸면 양쪽을 함께 갱신한다.
const easySubwayTopBarContentHeight = 60.0;

/// 네비/상단바 하단 구분선 색. 검색 박스 외곽선과 역할을 분리한다.
const easySubwayHeaderDividerColor = EasySubwayAccessibleColors.borderSubtle;

/// 상단바·시트와 본문을 나누는 1px 구분선.
///
/// 선 톤은 전 화면이 [easySubwayHeaderDividerColor]를 쓴다. 카카오식 짧은
/// 드롭은 노선도·좌측 메뉴만 [EasySubwayHeaderDivider.mapChrome]으로 켠다.
/// 그림자는 이 공용 위젯에만 두고 화면 파일에 직접 쓰지 않는다(#1933).
class EasySubwayHeaderDivider extends SizedBox {
  const EasySubwayHeaderDivider({super.key})
    : super(
        height: 1,
        width: double.infinity,
        child: const DecoratedBox(
          decoration: BoxDecoration(color: easySubwayHeaderDividerColor),
        ),
      );

  /// 노선도 상단바·좌측 메뉴 헤더용. 동일 선 톤 + 카카오식 짧은 드롭.
  ///
  /// 그림자 톤은 카카오 참조 스크린의 흰 지도 위 페이드
  /// (#CD→#E2→#EE→#F8→투명, ~5px)를 검정 반투명으로 그대로 환산했다.
  /// BoxShadow 근사 대신 짧은 페이드 드롭으로 길이와 색을 맞춘다.
  const EasySubwayHeaderDivider.mapChrome({super.key})
    : super(
        height: 1,
        width: double.infinity,
        child: const _EasySubwayMapChromeHeaderDivider(),
      );
}

/// 카카오 참조: 흰 배경 기준 205/226/238/248 → alpha 0x32/0x1D/0x11/0x07.
///
/// Material gradient decoration은 design_guard 하드 밴(#1915)이라
/// [CustomPaint] + `dart:ui` 셰이더로만 그린다.
const easySubwayMapChromeHeaderDropColors = <Color>[
  Color(0x32000000),
  Color(0x1D000000),
  Color(0x11000000),
  Color(0x07000000),
  Color(0x00000000),
];

/// [EasySubwayHeaderDivider.mapChrome] 본체. 1px 선 + 아래로 넘치는 짧은 드롭.
class _EasySubwayMapChromeHeaderDivider extends StatelessWidget {
  const _EasySubwayMapChromeHeaderDivider();

  @override
  Widget build(BuildContext context) {
    // 카카오 참조 페이드는 물리 픽셀 ~5px. logical height로 환산한다.
    final dropHeight = 5 / MediaQuery.devicePixelRatioOf(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const ColoredBox(
          color: easySubwayHeaderDividerColor,
          child: SizedBox.expand(),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 1,
          height: dropHeight,
          child: IgnorePointer(
            child: CustomPaint(
              painter: const _MapChromeHeaderDropPainter(),
              child: SizedBox(height: dropHeight, width: double.infinity),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapChromeHeaderDropPainter extends CustomPainter {
  const _MapChromeHeaderDropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, size.height),
        easySubwayMapChromeHeaderDropColors,
        const <double>[0, 0.25, 0.5, 0.75, 1],
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _MapChromeHeaderDropPainter oldDelegate) =>
      false;
}

EdgeInsets easySubwayBottomActionInsets(
  BuildContext context, {
  double horizontal = 20,
  double top = 8,
  double bottom = 32,
}) {
  final viewPadding = MediaQuery.viewPaddingOf(context);
  final viewInsets = MediaQuery.viewInsetsOf(context);
  final left = viewPadding.left > horizontal ? viewPadding.left : horizontal;
  final right = viewPadding.right > horizontal ? viewPadding.right : horizontal;
  final bottomInset = viewInsets.bottom > viewPadding.bottom
      ? viewInsets.bottom
      : viewPadding.bottom;
  return EdgeInsets.fromLTRB(left, top, right, bottom + bottomInset);
}

class AccessibleShortcutButton extends StatelessWidget {
  const AccessibleShortcutButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    super.key,
  });

  final VoidCallback onPressed;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        alignment: Alignment.center,
        backgroundColor: EasySubwayAccessibleColors.surface,
        foregroundColor: EasySubwayAccessibleColors.primary,
        minimumSize: const Size.fromHeight(EasySubwayTouchTarget.general),
        side: BorderSide(color: colorScheme.outlineVariant),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      icon: IconTheme.merge(data: const IconThemeData(size: 22), child: icon),
      label: Text(label, textAlign: TextAlign.center),
    );
  }
}

class AccessibleStateCard extends StatelessWidget {
  const AccessibleStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$title, $subtitle',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colorScheme.primary, size: 28),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[const SizedBox(height: 12), ...actions],
        ],
      ),
    );
  }
}
