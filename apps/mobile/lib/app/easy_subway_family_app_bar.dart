import 'package:flutter/material.dart';

import '../accessible_design.dart';

/// 설정·내 제보와 동일한 패밀리룩 AppBar chrome.
///
/// toolbarHeight 60, [EasySubwayAccessibleColors.topBarSurface], 커스텀 back,
/// [EasySubwayHeaderDivider], elevation 0, surfaceTint transparent.
class EasySubwayFamilyAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const EasySubwayFamilyAppBar({
    required this.title,
    this.actions,
    this.leading,
    this.onBack,
    this.backButtonKey,
    this.dividerKey,
    super.key,
  });

  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;
  final VoidCallback? onBack;
  final Key? backButtonKey;
  final Key? dividerKey;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      toolbarHeight: 60,
      backgroundColor: EasySubwayAccessibleColors.topBarSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      actions: actions,
      leading:
          leading ??
          IconButton(
            key: backButtonKey ?? const Key('easySubwayFamilyAppBarBack'),
            tooltip: '뒤로',
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            style: IconButton.styleFrom(
              minimumSize: const Size.square(EasySubwayTouchTarget.general),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(
              Icons.arrow_back,
              size: 26,
              color: Color(0xFF4B4B4B),
            ),
          ),
      flexibleSpace: Align(
        alignment: Alignment.bottomCenter,
        child: EasySubwayHeaderDivider(key: dividerKey),
      ),
    );
  }
}
