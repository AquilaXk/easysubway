import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';

const _stationFacilityStatusSummaryRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.sheet),
);

class StationFacilityStatusSummary extends StatelessWidget {
  const StationFacilityStatusSummary({
    required this.text,
    required this.semanticLabel,
    super.key,
  });

  final String text;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Card(
          margin: EdgeInsets.zero,
          color: EasySubwayAccessibleColors.redSoft,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: _stationFacilityStatusSummaryRadius,
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber,
                  color: EasySubwayAccessibleColors.red,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: EasySubwayAccessibleColors.red,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
