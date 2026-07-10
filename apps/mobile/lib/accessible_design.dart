import 'package:flutter/material.dart';

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

  // --- Surface & 중립 위계 ---
  /// 기본 표면(플랫 화이트).
  static const surface = Colors.white;

  /// 본문 텍스트.
  static const text = Color(0xFF102A2C);

  /// 보조 텍스트.
  static const secondaryText = Color(0xFF29484B);

  /// 흐린 텍스트·비활성.
  static const mutedText = Color(0xFF466467);

  /// 구분선·얇은 테두리.
  static const line = Color(0xFFDBE3E9);

  /// 목록 행 라벨 (기준 화면 좌측 메뉴의 행 텍스트 톤).
  static const listRowText = Color(0xFF1E3234);

  /// 섹션 캡션·부제 (기준 화면 좌측 메뉴의 섹션 톤).
  static const caption = Color(0xFF7C949A);

  /// 보조 아이콘 (기준 화면 검색바 아이콘 톤).
  static const iconMuted = Color(0xFF8A9AA0);

  /// 셰브런·디스클로저·비활성 아이콘.
  static const disclosure = Color(0xFFB0BEC5);

  // --- 브랜드 액센트 (1계열) ---
  /// 앱 전체 단일 브랜드 액센트.
  static const primary = Color(0xFF006D77);

  /// 과거 navy 액센트. 단일 브랜드 액센트로 통일했다. 신규 코드는 [primary] 사용.
  static const brand = primary;

  /// 다크 히어로 등 짙은 브랜드 표면(레거시). 신규 화면에서는 사용하지 않는다.
  static const brandDark = Color(0xFF071B2F);

  // --- 상태색: 정상/복구 (success) ---
  /// 정상·복구 상태 텍스트/아이콘.
  static const mint = Color(0xFF0A705A);

  /// 정상·복구 상태 강조.
  static const mintDark = Color(0xFF075D4B);

  /// 정상·복구 상태 배경 틴트.
  static const mintSoft = Color(0xFFF0FBF7);

  /// 정상·복구 상태 테두리.
  static const mintBorder = Color(0xFFCBEADD);

  // --- 상태색: 주의 (warning) ---
  /// 주의 상태 텍스트/아이콘.
  static const amber = Color(0xFF9A5600);

  /// 주의 상태 배경 틴트.
  static const amberSoft = Color(0xFFFFF0D1);

  // --- 상태색: 고장·오류 (danger) ---
  /// 고장·오류 상태 텍스트/아이콘.
  static const red = Color(0xFFB42318);

  /// 고장·오류 상태 배경 틴트.
  static const redSoft = Color(0xFFFFE8E6);

  /// 확인 중·제보됨(needsInfo) 상태색. 브랜드 액센트 1계열로 통일한다.
  static const needsInfo = primary;

  /// 정보 틴트(레거시). 장식용이므로 화면 정비 시 여백·구분선으로 대체한다.
  static const skySoft = Color(0xFFE6F5FF);

  // --- 공용 표면·컨트롤 토큰 ---
  /// 스캐폴드 기본 배경(플랫 화이트에 아주 옅은 그레이).
  static const scaffoldSurface = Color(0xFFF6F8F9);

  /// 카드 그림자(최소 그림자 원칙).
  static const cardShadow = Color(0x0A071B2F);

  /// 스위치 켜짐 트랙(브랜드 액센트 1계열).
  static const switchActiveTrack = primary;

  /// 스위치 꺼짐 트랙.
  static const switchInactiveTrack = Color(0xFFC8D3DC);

  // --- 지도 오버레이 전용 ---
  // 지도 배경 시인성 때문에 브랜드 액센트로 수렴하지 않는다 (기준 화면 실측 값).

  /// 지도 위 선택 역 말풍선 톤(밝은 시안).
  static const mapSelectionAccent = Color(0xFF13B8D6);

  /// 지도 위 지역 선택 칩 톤(밝은 블루).
  static const mapRegionAccent = Color(0xFF006FD6);

  // --- 고대비 모드 ---
  static const highContrastText = Color(0xFF000000);
  static const highContrastPrimary = Color(0xFF003D40);
  static const highContrastSecondary = Color(0xFF005E68);
}

class EasySubwayTouchTarget {
  const EasySubwayTouchTarget._();

  static const iconOnly = 48.0;
  static const general = 56.0;
  static const primary = 60.0;
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
