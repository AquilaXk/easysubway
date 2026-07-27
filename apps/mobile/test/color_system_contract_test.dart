import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/accessible_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('color system JSON과 Dart 정적 색상 계약이 일치한다', () {
    final colorSystem =
        jsonDecode(
              File(
                '../../tools/design/easysubway-color-system.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final primitives = colorSystem['primitives'] as Map<String, dynamic>;
    final semantic = colorSystem['semantic'] as Map<String, dynamic>;

    final primitiveColors = <String, Color>{
      'brand.50': EasySubwayColorPrimitives.brand50,
      'brand.100': EasySubwayColorPrimitives.brand100,
      'brand.200': EasySubwayColorPrimitives.brand200,
      'brand.300': EasySubwayColorPrimitives.brand300,
      'brand.400': EasySubwayColorPrimitives.brand400,
      'brand.500': EasySubwayColorPrimitives.brand500,
      'brand.600': EasySubwayColorPrimitives.brand600,
      'brand.700': EasySubwayColorPrimitives.brand700,
      'brand.800': EasySubwayColorPrimitives.brand800,
      'brand.900': EasySubwayColorPrimitives.brand900,
      'brand.950': EasySubwayColorPrimitives.brand950,
      'neutral.white': EasySubwayColorPrimitives.neutralWhite,
      'neutral.scaffold': EasySubwayColorPrimitives.neutralScaffold,
      'neutral.subtle': EasySubwayColorPrimitives.neutralSubtle,
      'neutral.border': EasySubwayColorPrimitives.neutralBorder,
      'ink.secondary': EasySubwayColorPrimitives.inkSecondary,
      'ink.muted': EasySubwayColorPrimitives.inkMuted,
      'status.success': EasySubwayColorPrimitives.statusSuccess,
      'status.warning': EasySubwayColorPrimitives.statusWarning,
      'status.danger': EasySubwayColorPrimitives.statusDanger,
      'status.info': EasySubwayColorPrimitives.statusInfo,
      'status.successSoft': EasySubwayColorPrimitives.statusSuccessSoft,
      'status.warningSoft': EasySubwayColorPrimitives.statusWarningSoft,
      'status.dangerSoft': EasySubwayColorPrimitives.statusDangerSoft,
      'status.infoSoft': EasySubwayColorPrimitives.statusInfoSoft,
    };
    final semanticColors = <String, Color>{
      'surface.default': EasySubwayAccessibleColors.surfaceDefault,
      'surface.scaffold': EasySubwayAccessibleColors.surfaceScaffold,
      'surface.subtle': EasySubwayAccessibleColors.surfaceSubtle,
      'surface.brandChrome': EasySubwayAccessibleColors.surfaceBrandChrome,
      'surface.brand': EasySubwayAccessibleColors.surfaceBrand,
      'surface.brandStrong': EasySubwayAccessibleColors.surfaceBrandStrong,
      'surface.signature': EasySubwayAccessibleColors.surfaceSignature,
      'border.subtle': EasySubwayAccessibleColors.borderSubtle,
      'content.primary': EasySubwayAccessibleColors.contentPrimary,
      'content.secondary': EasySubwayAccessibleColors.contentSecondary,
      'content.muted': EasySubwayAccessibleColors.contentMuted,
      'interaction.primary': EasySubwayAccessibleColors.interactionPrimary,
      'interaction.primaryPressed':
          EasySubwayAccessibleColors.interactionPrimaryPressed,
      'interaction.onPrimary': EasySubwayAccessibleColors.interactionOnPrimary,
      'interaction.secondarySurface':
          EasySubwayAccessibleColors.interactionSecondarySurface,
      'interaction.secondaryBorder':
          EasySubwayAccessibleColors.interactionSecondaryBorder,
      'interaction.secondaryPressedSurface':
          EasySubwayAccessibleColors.interactionSecondaryPressedSurface,
      'interaction.secondaryPressedBorder':
          EasySubwayAccessibleColors.interactionSecondaryPressedBorder,
      'interaction.onSignatureBorder':
          EasySubwayAccessibleColors.interactionOnSignatureBorder,
      'interaction.onBrand': EasySubwayAccessibleColors.interactionOnBrand,
      'focus.default': EasySubwayAccessibleColors.focusDefault,
      'focus.onSignature': EasySubwayAccessibleColors.focusOnSignature,
      'decorative.divider': EasySubwayAccessibleColors.decorativeDivider,
      'status.successContent': EasySubwayAccessibleColors.statusSuccessContent,
      'status.successSurface': EasySubwayAccessibleColors.statusSuccessSurface,
      'status.warningContent': EasySubwayAccessibleColors.statusWarningContent,
      'status.warningSurface': EasySubwayAccessibleColors.statusWarningSurface,
      'status.dangerContent': EasySubwayAccessibleColors.statusDangerContent,
      'status.dangerSurface': EasySubwayAccessibleColors.statusDangerSurface,
      'status.infoContent': EasySubwayAccessibleColors.statusInfoContent,
      'status.infoSurface': EasySubwayAccessibleColors.statusInfoSurface,
    };

    final expectedPrimitives = primitives.map(
      (key, hex) => MapEntry(
        key,
        Color(int.parse('FF${(hex as String).substring(1)}', radix: 16)),
      ),
    );
    final expectedSemantic = semantic.map(
      (key, primitiveKey) => MapEntry(
        key,
        Color(
          int.parse(
            'FF${(primitives[primitiveKey] as String).substring(1)}',
            radix: 16,
          ),
        ),
      ),
    );

    expect(colorSystem['version'], 1);
    expect(primitiveColors, expectedPrimitives);
    expect(semanticColors, expectedSemantic);
  });
}
