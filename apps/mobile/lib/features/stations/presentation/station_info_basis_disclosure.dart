import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';

const _stationInfoBasisCardRadius = BorderRadius.all(
  Radius.circular(EasySubwayRadius.sheet),
);

class StationInfoBasisDisclosure extends StatefulWidget {
  const StationInfoBasisDisclosure({required this.labels, super.key});

  final List<String> labels;

  @override
  State<StationInfoBasisDisclosure> createState() =>
      _StationInfoBasisDisclosureState();
}

class _StationInfoBasisDisclosureState
    extends State<StationInfoBasisDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels
        .where((label) => label.trim().isNotEmpty)
        .toList(growable: false);
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            size: 24,
          ),
          label: Text(_expanded ? '안내 확인 방법 접기' : '안내 확인 방법 보기'),
        ),
        if (_expanded) ...[
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            color: EasySubwayAccessibleColors.surfaceDefault,
            shape: const RoundedRectangleBorder(
              borderRadius: _stationInfoBasisCardRadius,
              side: BorderSide(color: EasySubwayAccessibleColors.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '안내 확인 방법',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final label in labels) ...[
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: EasySubwayAccessibleColors.mutedText,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (label != labels.last) const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
