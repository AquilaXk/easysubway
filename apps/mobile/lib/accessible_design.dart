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
  double bottom = 20,
}) {
  return EdgeInsets.fromLTRB(
    horizontal,
    top,
    horizontal,
    bottom + MediaQuery.viewPaddingOf(context).bottom,
  );
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
