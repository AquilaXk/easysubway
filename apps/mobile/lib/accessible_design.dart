import 'package:flutter/material.dart';

/// 노선도 화면을 기준으로 삼는 앱 공용 색 팔레트.
///
/// 역할별로 상수를 묶어 화면마다 색이 섞이지 않게 한다.
/// - 브랜드 액센트는 [primary] 1계열만 사용한다. 과거 navy 액센트([brand])는
///   이 액센트로 통일했다.
/// - 상태색(정상/주의/고장)은 의미가 있는 곳에만 쓴다.
/// - soft 틴트 배경은 상태 표현용이며 장식용으로 쓰지 않는다.
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

  /// 정보 틴트(레거시). 장식용이므로 화면 정비 시 여백·구분선으로 대체한다.
  static const skySoft = Color(0xFFE6F5FF);
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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: EasySubwayAccessibleColors.mintSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: colorScheme.primary, size: 28),
              ),
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
