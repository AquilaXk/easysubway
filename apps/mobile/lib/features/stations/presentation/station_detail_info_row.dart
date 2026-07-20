import 'package:flutter/material.dart';

import '../../../accessible_design.dart';

class StationDetailInfoRow extends StatelessWidget {
  const StationDetailInfoRow({
    required this.icon,
    required this.text,
    super.key,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: EasySubwayAccessibleColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: EasySubwayAccessibleColors.secondaryText,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
