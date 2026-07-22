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

  // --- 브랜드 액센트 (무채색 잉크 1계열) ---
  /// 앱 전체 단일 브랜드 액센트. 초록(teal) 대신 무채색 차콜 잉크로 통일한다.
  /// 화면의 유채색은 노선 색(데이터)뿐이며, 액센트는 CTA·선택·링크에만 쓴다.
  static const primary = Color(0xFF2A2F31);

  /// 과거 navy 액센트. 단일 브랜드 액센트로 통일했다. 신규 코드는 [primary] 사용.
  static const brand = primary;

  /// 시그니처 라벤더 팔레트(라이트 단일 모드).
  /// 기준색은 흰 글자 대비 5.7:1(AA 통과)이며 CTA·활성 컨트롤에 쓴다.
  static const brandSignature = Color(0xFF7C3AED);

  /// 포커스·강조 아이콘에 쓰는 중간 라벤더.
  static const brandSignatureMedium = Color(0xFFAA7FF3);

  /// 선택 배경·강조선에 쓰는 연한 라벤더.
  static const brandSignatureSoft = Color(0xFFD8C4FA);

  /// 선택 영역에 쓰는 가장 연한 라벤더.
  static const brandSignatureSurface = Color(0xFFF5EFFE);

  /// 흰색에 가까운 전역 상단바 라벤더.
  static const topBarSurface = Color(0xFFFAF8FF);

  /// 플레이스홀더보다 연한 공용 검색창 중성 배경.
  static const searchFieldSurface = Color(0xFFF6F8F9);

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

  /// 주의 상태 테두리.
  static const amberBorder = Color(0xFFF1D49A);

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

  /// 스위치 켜짐 트랙.
  static const switchActiveTrack = brandSignature;

  /// 스위치 꺼짐 트랙.
  static const switchInactiveTrack = Color(0xFFC8D3DC);

  // --- 지도 오버레이 전용 ---
  // 지도 배경 시인성 때문에 브랜드 액센트로 수렴하지 않는다 (기준 화면 실측 값).

  /// 지도 위 선택 역 말풍선 톤(밝은 시안).
  static const mapSelectionAccent = Color(0xFF13B8D6);

  /// 지도 위 지역 선택 칩 톤(밝은 블루).
  static const mapRegionAccent = Color(0xFF006FD6);

  // --- 홈 신규 알림 안내 바 (오너 스펙 2026-07-16, #2200) ---
  /// 신규 알림 안내 바 배경.
  static const noticeBarSurface = Color(0xFFFFF7ED);

  /// 신규 알림 안내 바 하단 테두리(1dp).
  static const noticeBarBorder = Color(0xFFF2DFC8);

  /// 신규 알림 안내 바 기본 문구.
  static const noticeBarText = Color(0xFF5D4932);

  /// 신규 알림 안내 바 벨 아이콘·"알림 보기".
  static const noticeBarAccent = Color(0xFF8F4B1E);

  // --- 주변역 패널 실시간/시간표 토글 (오너 스펙 2026-07-16, #2200) ---
  /// 토글 비선택 세그먼트 배경.
  static const nearbyToggleIdleFill = Color(0xFFF6F6F8);

  /// 토글 비선택 세그먼트 글자.
  static const nearbyToggleIdleText = Color(0xFF70717B);

  /// 좌우 열차 정보 구분선.
  static const arrivalColumnDivider = Color(0xFFDEDEE3);

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

/// 네비/상단바 하단 구분선 색. 카카오 지하철 상단 카드 하단 엣지 실측
/// 뉴트럴 그레이(#D5D5D5). 예전 청회색(#CBD6DD)은 선이 탁하고 두껍게 보였다.
const easySubwayHeaderDividerColor = Color(0xFFD5D5D5);

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
  /// BoxShadow 근사 대신 그라데이션을 써서 길이와 색을 맞춘다.
  const EasySubwayHeaderDivider.mapChrome({super.key})
    : super(
        height: 1,
        width: double.infinity,
        child: const _EasySubwayMapChromeHeaderDivider(),
      );
}

/// [EasySubwayHeaderDivider.mapChrome] 본체. 1px 선 + 아래로 넘치는 짧은 드롭.
class _EasySubwayMapChromeHeaderDivider extends StatelessWidget {
  const _EasySubwayMapChromeHeaderDivider();

  /// 카카오 참조: 흰 배경 기준 205/226/238/248 → alpha 0x32/0x1D/0x11/0x07.
  static const List<Color> _dropColors = <Color>[
    Color(0x32000000),
    Color(0x1D000000),
    Color(0x11000000),
    Color(0x07000000),
    Color(0x00000000),
  ];

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
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _dropColors,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
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
