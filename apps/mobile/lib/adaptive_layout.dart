import 'package:flutter/widgets.dart';

class EasySubwayAdaptiveLayout {
  const EasySubwayAdaptiveLayout._();

  static const double largeScreenMinWidth = 840;
  static const double largeScreenMaxContentWidth = 1180;
  static const double largeScreenGutter = 24;
  static const double largeScreenColumnGap = 18;

  static bool isLargeScreen(
    BoxConstraints constraints, {
    double textScaleFactor = 1,
  }) {
    final minWidth = textScaleFactor >= 1.6 ? 1024 : largeScreenMinWidth;
    return constraints.maxWidth >= minWidth;
  }
}
