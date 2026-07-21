import 'package:flutter/material.dart';

import '../../../accessible_design.dart';
import '../../../design_tokens.dart';

/// 홈·역 검색 상단바 지역 메뉴 항목.
class EasySubwayRegionMenuItem {
  const EasySubwayRegionMenuItem({required this.id, required this.label});

  /// 원본 지역 키(예: `부산권`, `수도권`).
  final String id;

  /// UI 표시명(예: `부산`, `수도권`).
  final String label;
}

/// 트리거 바로 아래·화면 우측 밀착으로 지역 메뉴를 연다.
Future<void> showEasySubwayRegionMenu({
  required BuildContext triggerContext,
  required List<EasySubwayRegionMenuItem> regions,
  required String selectedRegion,
  required ValueChanged<String> onRegionSelected,
}) async {
  final available = regions.isEmpty
      ? const [EasySubwayRegionMenuItem(id: '수도권', label: '수도권')]
      : regions;
  final RenderBox? triggerBox = triggerContext.findRenderObject() as RenderBox?;
  final RenderBox? overlayBox =
      Overlay.of(triggerContext).context.findRenderObject() as RenderBox?;
  if (triggerBox == null || overlayBox == null) {
    return;
  }
  final topRight = triggerBox.localToGlobal(
    triggerBox.size.bottomRight(Offset.zero),
    ancestor: overlayBox,
  );
  await showGeneralDialog<String>(
    context: triggerContext,
    barrierDismissible: true,
    barrierLabel: '지역 메뉴 닫기',
    barrierColor: const Color(0x99000000),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: topRight.dy,
            right: 0,
            child: EasySubwayRegionMenuPanel(
              availableRegions: available,
              selectedRegion: selectedRegion,
              onRegionSelected: onRegionSelected,
            ),
          ),
        ],
      );
    },
  );
}

class EasySubwayRegionMenuPanel extends StatelessWidget {
  const EasySubwayRegionMenuPanel({
    required this.availableRegions,
    required this.selectedRegion,
    required this.onRegionSelected,
    super.key,
  });

  final List<EasySubwayRegionMenuItem> availableRegions;
  final String selectedRegion;
  final ValueChanged<String> onRegionSelected;

  bool _isSelected(EasySubwayRegionMenuItem region) {
    return region.id == selectedRegion || region.label == selectedRegion;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < availableRegions.length; i++) {
      final region = availableRegions[i];
      final isSelected = _isSelected(region);
      rows.add(
        InkWell(
          key: ValueKey('networkMapRegionMenuRow_${region.id}'),
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onTap: () {
            onRegionSelected(region.id);
            Navigator.of(context).pop();
          },
          child: ColoredBox(
            color: isSelected
                ? EasySubwayAccessibleColors.brandSignatureSurface
                : Colors.transparent,
            child: SizedBox(
              height: EasySubwayTouchTarget.general,
              child: Semantics(
                button: true,
                selected: isSelected,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          region.label,
                          style: TextStyle(
                            color: isSelected
                                ? EasySubwayAccessibleColors.brandSignature
                                : EasySubwayAccessibleColors.listRowText,
                            fontSize: 16,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.check,
                          color: EasySubwayAccessibleColors.brandSignature,
                          size: 20,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      if (i != availableRegions.length - 1) {
        rows.add(const _EasySubwayRegionMenuDivider());
      }
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: IntrinsicWidth(
        child: Material(
          elevation: 0,
          color: EasySubwayAccessibleColors.surface,
          surfaceTintColor: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: EasySubwayAccessibleColors.line),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(EasySubwayRadius.control),
              bottomLeft: Radius.circular(EasySubwayRadius.control),
              topRight: Radius.zero,
              bottomRight: Radius.zero,
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }
}

class _EasySubwayRegionMenuDivider extends StatelessWidget {
  const _EasySubwayRegionMenuDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      key: Key('networkMapRegionMenuDivider'),
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: EasySubwayAccessibleColors.line),
      ),
    );
  }
}
