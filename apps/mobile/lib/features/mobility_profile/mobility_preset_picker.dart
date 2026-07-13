/// 보행 프리셋 선택 공용 컴포넌트.
///
/// 온보딩 step0와 설정·길찾기 진입점이 같은 행 위젯(`MobilityPresetRow`)과
/// 바텀시트(`showMobilityPresetSheet`)를 공유한다. 무채색만 사용하고 Card·그림자·
/// gradient·리플을 두지 않는다(#1703 디자인 제약).
library;

import 'package:flutter/material.dart';

import '../../accessible_design.dart';
import '../../design_tokens.dart';
import 'mobility_preset_labels.dart';
import 'mobility_profile_policy.dart';

/// 바텀시트에 노출하는 프리셋 순서(표준 → 천천히 → 계단 없이 → 휠체어).
const List<MobilityPreset> mobilityPresetSheetOrder = <MobilityPreset>[
  MobilityPreset.standard,
  MobilityPreset.slow,
  MobilityPreset.noStairs,
  MobilityPreset.stepFree,
];

/// 프리셋 선택 바텀시트. 다른 프리셋을 고르면 그 프리셋을 반환하고, 취소·재선택이
/// 없으면 null을 반환한다.
Future<MobilityPreset?> showMobilityPresetSheet(
  BuildContext context, {
  required MobilityPreset current,
}) {
  return showModalBottomSheet<MobilityPreset>(
    context: context,
    backgroundColor: EasySubwayAccessibleColors.surface,
    builder: (sheetContext) {
      final textTheme = Theme.of(sheetContext).textTheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: EasySubwaySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  EasySubwaySpacing.xl,
                  EasySubwaySpacing.sm,
                  EasySubwaySpacing.xl,
                  EasySubwaySpacing.sm,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    '걷는 속도',
                    style: textTheme.titleMedium?.copyWith(
                      color: EasySubwayAccessibleColors.text,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (
                        var i = 0;
                        i < mobilityPresetSheetOrder.length;
                        i++
                      ) ...[
                        if (i != 0)
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: EasySubwayAccessibleColors.line,
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: EasySubwaySpacing.xl,
                          ),
                          child: MobilityPresetRow(
                            preset: mobilityPresetSheetOrder[i],
                            selected: mobilityPresetSheetOrder[i] == current,
                            showDescription: true,
                            onTap: () => Navigator.of(sheetContext)
                                .pop(mobilityPresetSheetOrder[i]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 단일 프리셋 행. 온보딩·시트가 공유한다. 무채색 라인 아이콘 + 표시명(+부가설명).
/// 선택 시 우측 체크. 리플 방지를 위해 GestureDetector(opaque)를 쓴다.
class MobilityPresetRow extends StatelessWidget {
  const MobilityPresetRow({
    required this.preset,
    required this.selected,
    required this.onTap,
    this.showDescription = false,
    super.key,
  });

  final MobilityPreset preset;
  final bool selected;
  final VoidCallback onTap;

  /// true면 표시명 아래 부가설명도 노출한다(온보딩·시트).
  final bool showDescription;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = mobilityPresetDisplayName(preset);
    final description = mobilityPresetDescription(preset);
    final semanticsLabel = '$title, $description';
    return Semantics(
      label: semanticsLabel,
      selected: selected,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: Key('mobilityPresetRow-${preset.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Icon(
                    mobilityPresetIcon(preset),
                    size: 24,
                    color: selected
                        ? EasySubwayAccessibleColors.text
                        : EasySubwayAccessibleColors.mutedText,
                  ),
                  const SizedBox(width: EasySubwaySpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          style: textTheme.bodyLarge?.copyWith(
                            color: EasySubwayAccessibleColors.text,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            fontSize: 18,
                            height: 1.25,
                          ),
                        ),
                        if (showDescription) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: textTheme.bodyMedium?.copyWith(
                              color: EasySubwayAccessibleColors.mutedText,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: EasySubwaySpacing.md),
                  if (selected)
                    const Icon(
                      Icons.check,
                      size: 22,
                      color: EasySubwayAccessibleColors.primary,
                    )
                  else
                    const SizedBox(width: 22),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
