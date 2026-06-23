import 'package:flutter/material.dart';

class StationSearchLine {
  const StationSearchLine({
    required this.id,
    required this.name,
    required this.color,
    required this.stationCode,
  });

  factory StationSearchLine.fromJson(Map<String, Object?> json) {
    return StationSearchLine(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      color: _requiredString(json, 'color'),
      stationCode: _requiredString(json, 'stationCode'),
    );
  }

  final String id;
  final String name;
  final String color;
  final String stationCode;

  String get badgeText => stationLineBadgeText(name);

  Color get badgeColor => stationLineColor(color);
}

String stationLineBadgeText(String name) {
  const knownBadgeLabels = <String, String>{
    '경의중앙': '경의중앙',
    '수인분당': '수인분당',
    '신분당': '신분당',
    '인천1': '인천1',
    '인천2': '인천2',
  };
  for (final entry in knownBadgeLabels.entries) {
    if (name.contains(entry.key)) {
      return entry.value;
    }
  }

  final numberedLine = RegExp(r'(\d+)\s*호선').firstMatch(name);
  if (numberedLine != null) {
    return numberedLine.group(1) ?? name;
  }

  final compactName = name
      .replaceAll('수도권 ', '')
      .replaceAll('광역 ', '')
      .replaceAll('선', '')
      .trim();
  if (compactName.length <= 4) {
    return compactName;
  }
  return compactName.substring(0, 4);
}

Color stationLineColor(String color) {
  final normalized = color.trim().replaceFirst('#', '');
  if (normalized.length == 6) {
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed != null) {
      return Color(0xFF000000 | parsed);
    }
  }
  return const Color(0xFF006D77);
}

Color stationLineTextColor(Color backgroundColor) {
  const darkText = Color(0xFF102A2C);
  final darkContrast = _contrastRatio(backgroundColor, darkText);
  final lightContrast = _contrastRatio(backgroundColor, Colors.white);
  return darkContrast >= lightContrast ? darkText : Colors.white;
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance() + 0.05;
  final secondLuminance = second.computeLuminance() + 0.05;
  if (firstLuminance > secondLuminance) {
    return firstLuminance / secondLuminance;
  }
  return secondLuminance / firstLuminance;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required station field: $key');
}
