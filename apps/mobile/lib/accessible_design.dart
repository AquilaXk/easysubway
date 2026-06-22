import 'package:flutter/material.dart';

class EasySubwayAccessibleColors {
  const EasySubwayAccessibleColors._();

  static const primary = Color(0xFF006D77);
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
