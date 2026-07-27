import 'package:flutter/material.dart';

import '../accessible_design.dart';
import '../favorite_facility.dart';

const mainPagePadding = EdgeInsets.fromLTRB(20, 20, 20, 32);
const mainListPagePadding = EdgeInsets.fromLTRB(17, 18, 17, 32);
const _appSectionTitlePadding = EdgeInsets.fromLTRB(1, 22, 1, 11);

const mainThemeControlRadius = BorderRadius.all(Radius.circular(12));

class AppSectionTitle extends StatelessWidget {
  // ignore: use_key_in_widget_constructors
  const AppSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: _appSectionTitlePadding,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: EasySubwayAccessibleColors.text,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}

bool isFacilityAlert(FavoriteFacility facility) {
  return facility.needsAttention;
}

class HomeStateCard extends StatelessWidget {
  const HomeStateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final actionLabel = this.actionLabel;
    return AppCard(
      showBorder: true,
      child: AccessibleStateCard(
        icon: icon,
        title: title,
        subtitle: subtitle,
        actions: [
          if (actionLabel != null && onAction != null)
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh),
              label: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  // ignore: use_key_in_widget_constructors
  const AppCard({
    required this.child,
    this.backgroundColor = EasySubwayAccessibleColors.surfaceDefault,
    this.borderColor = EasySubwayAccessibleColors.line,
    this.showBorder = true,
  });

  final Widget child;
  final Color backgroundColor;
  final Color borderColor;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    // 최소 그림자 원칙: 그림자 대신 얇은 보더로 카드를 구분한다.
    return Card(
      margin: EdgeInsets.zero,
      color: backgroundColor,
      elevation: 0,
      shadowColor: EasySubwayAccessibleColors.cardShadow,
      shape: RoundedRectangleBorder(
        side: showBorder ? BorderSide(color: borderColor) : BorderSide.none,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }
}

class AppInfoRow extends StatelessWidget {
  // ignore: use_key_in_widget_constructors
  const AppInfoRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final leading = SizedBox(
      width: 32,
      height: 32,
      child: Center(child: Icon(icon, color: iconColor, size: 22)),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: EasySubwayAccessibleColors.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        if (subtitle != null && subtitle.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              color: EasySubwayAccessibleColors.mutedText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
    return Row(
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(child: content),
      ],
    );
  }
}

class FeatureTile extends StatelessWidget {
  const FeatureTile({
    required this.icon,
    required this.title,
    required this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return MergeSemantics(
      child: Semantics(
        label: semanticLabel,
        child: ExcludeSemantics(
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: EasySubwayAccessibleColors.surfaceDefault,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: mainThemeControlRadius,
              side: const BorderSide(color: EasySubwayAccessibleColors.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(icon, color: colorScheme.primary, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: EasySubwayAccessibleColors.text,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
