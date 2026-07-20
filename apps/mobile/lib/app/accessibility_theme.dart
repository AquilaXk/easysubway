import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../accessible_design.dart';
import '../onboarding.dart';

class OnboardingPreferenceScope extends StatelessWidget {
  // ignore: use_key_in_widget_constructors
  const OnboardingPreferenceScope({
    required this.preferences,
    required this.child,
  });

  final OnboardingViewPreferences preferences;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return MediaQuery(
      data: mediaQuery.copyWith(
        highContrast:
            preferences.highContrastEnabled || mediaQuery.highContrast,
      ),
      child: Theme(
        data: _themeForPlatformAccessibility(
          _themeForPreferences(Theme.of(context), preferences),
          mediaQuery,
        ),
        child: child,
      ),
    );
  }
}

ThemeData _themeForPreferences(
  ThemeData baseTheme,
  OnboardingViewPreferences preferences,
) {
  if (!preferences.highContrastEnabled) {
    return baseTheme;
  }

  final colorScheme = baseTheme.colorScheme.copyWith(
    primary: EasySubwayAccessibleColors.highContrastPrimary,
    onPrimary: Colors.white,
    secondary: EasySubwayAccessibleColors.highContrastSecondary,
    onSecondary: Colors.white,
    surface: Colors.white,
    onSurface: EasySubwayAccessibleColors.highContrastText,
    outline: EasySubwayAccessibleColors.highContrastText,
  );

  return baseTheme.copyWith(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: baseTheme.appBarTheme.copyWith(
      backgroundColor: Colors.white,
      foregroundColor: EasySubwayAccessibleColors.highContrastText,
      titleTextStyle: baseTheme.appBarTheme.titleTextStyle?.copyWith(
        color: EasySubwayAccessibleColors.highContrastText,
      ),
    ),
    // 보조 버튼이 중립 보더로 바뀌었으므로 고대비에서 보더·텍스트 대비를 보정.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: baseTheme.outlinedButtonTheme.style?.copyWith(
        foregroundColor: const WidgetStatePropertyAll(
          EasySubwayAccessibleColors.highContrastPrimary,
        ),
        side: const WidgetStatePropertyAll(
          BorderSide(
            color: EasySubwayAccessibleColors.highContrastText,
            width: 1.5,
          ),
        ),
      ),
    ),
  );
}

ThemeData _themeForPlatformAccessibility(
  ThemeData baseTheme,
  MediaQueryData mediaQuery,
) {
  if (!mediaQuery.boldText) {
    return baseTheme;
  }

  return baseTheme.copyWith(
    textTheme: _boldTextTheme(baseTheme.textTheme),
    primaryTextTheme: _boldTextTheme(baseTheme.primaryTextTheme),
    appBarTheme: baseTheme.appBarTheme.copyWith(
      titleTextStyle: _boldTextStyle(baseTheme.appBarTheme.titleTextStyle),
      toolbarTextStyle: _boldTextStyle(baseTheme.appBarTheme.toolbarTextStyle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _boldButtonTextStyle(baseTheme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _boldButtonTextStyle(baseTheme.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _boldButtonTextStyle(baseTheme.textButtonTheme.style),
    ),
  );
}

TextTheme _boldTextTheme(TextTheme textTheme) {
  return textTheme.copyWith(
    displayLarge: _boldTextStyle(textTheme.displayLarge),
    displayMedium: _boldTextStyle(textTheme.displayMedium),
    displaySmall: _boldTextStyle(textTheme.displaySmall),
    headlineLarge: _boldTextStyle(textTheme.headlineLarge),
    headlineMedium: _boldTextStyle(textTheme.headlineMedium),
    headlineSmall: _boldTextStyle(textTheme.headlineSmall),
    titleLarge: _boldTextStyle(textTheme.titleLarge),
    titleMedium: _boldTextStyle(textTheme.titleMedium),
    titleSmall: _boldTextStyle(textTheme.titleSmall),
    bodyLarge: _boldTextStyle(textTheme.bodyLarge),
    bodyMedium: _boldTextStyle(textTheme.bodyMedium),
    bodySmall: _boldTextStyle(textTheme.bodySmall),
    labelLarge: _boldTextStyle(textTheme.labelLarge),
    labelMedium: _boldTextStyle(textTheme.labelMedium),
    labelSmall: _boldTextStyle(textTheme.labelSmall),
  );
}

ButtonStyle _boldButtonTextStyle(ButtonStyle? baseStyle) {
  return (baseStyle ?? const ButtonStyle()).copyWith(
    textStyle: WidgetStateProperty.resolveWith((states) {
      return _boldTextStyle(baseStyle?.textStyle?.resolve(states));
    }),
  );
}

TextStyle _boldTextStyle(TextStyle? style) {
  final currentWeight = style?.fontWeight ?? FontWeight.w400;
  final currentIndex = FontWeight.values.indexOf(currentWeight);
  final minimumBoldIndex = FontWeight.values.indexOf(FontWeight.w700);
  final nextIndex = math.min(
    FontWeight.values.length - 1,
    math.max(currentIndex + 2, minimumBoldIndex),
  );
  return (style ?? const TextStyle()).copyWith(
    fontWeight: FontWeight.values[nextIndex],
  );
}
