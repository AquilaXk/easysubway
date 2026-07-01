import 'package:flutter/material.dart';

class EasySubwayAccessibleColors {
  const EasySubwayAccessibleColors._();

  static const primary = Color(0xFF006D77);
  static const brandDark = Color(0xFF071B2F);
  static const brand = Color(0xFF17527C);
  static const mint = Color(0xFF0A705A);
  static const mintDark = Color(0xFF075D4B);
  static const mintSoft = Color(0xFFF0FBF7);
  static const mintBorder = Color(0xFFCBEADD);
  static const amberSoft = Color(0xFFFFF0D1);
  static const amber = Color(0xFF9A5600);
  static const redSoft = Color(0xFFFFE8E6);
  static const red = Color(0xFFB42318);
  static const skySoft = Color(0xFFE6F5FF);
  static const line = Color(0xFFDBE3E9);
  static const text = Color(0xFF102A2C);
  static const secondaryText = Color(0xFF29484B);
  static const mutedText = Color(0xFF466467);
  static const surface = Colors.white;
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
                        fontWeight: FontWeight.w900,
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
