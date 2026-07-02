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

  String? get badgeAssetPath {
    final assetName = stationLineBadgeAssetNameFor(id: id, name: name);
    return assetName == null
        ? null
        : 'assets/metro_symbols/line_badges/$assetName';
  }
}

String? stationLineBadgeAssetNameFor({
  required String id,
  required String name,
}) {
  final source = '${id.toLowerCase()} ${name.toLowerCase()} $name';
  for (final entry in _stationLineBadgeAssetNames.entries) {
    if (source.contains(entry.key)) {
      return entry.value;
    }
  }
  final numberedLine = RegExp(r'(\d+)\s*호선').firstMatch(name);
  final number = numberedLine?.group(1);
  if (number == null) {
    return null;
  }
  if (_isBusanLine(id: id, name: name)) {
    return _bundledStationLineBadgeAssetName('busan_${number}_compact_256.png');
  }
  if (source.contains('daegu') || name.contains('대구')) {
    return _bundledStationLineBadgeAssetName('daegu_${number}_compact_256.png');
  }
  if (source.contains('daejeon') || name.contains('대전')) {
    return _bundledStationLineBadgeAssetName(
      'daejeon_${number}_compact_256.png',
    );
  }
  if (source.contains('gwangju') || name.contains('광주')) {
    return _bundledStationLineBadgeAssetName(
      'gwangju_${number}_compact_256.png',
    );
  }
  return _bundledStationLineBadgeAssetName('seoul_${number}_compact_256.png');
}

const _stationLineBadgeAssetNames = <String, String>{
  '부산김해': 'busan_gimhae_compact_256.png',
  'busan_gimhae': 'busan_gimhae_compact_256.png',
  'donghae': 'donghae_compact_256.png',
  '동해': 'donghae_compact_256.png',
  'gtx-a': 'gtx_a_compact_256.png',
  'gtx_a': 'gtx_a_compact_256.png',
  '경의중앙': 'gyeongui_jungang_compact_256.png',
  'gyeongui': 'gyeongui_jungang_compact_256.png',
  '수인분당': 'suin_bundang_compact_256.png',
  'suin': 'suin_bundang_compact_256.png',
  '신분당': 'shinbundang_compact_256.png',
  'shinbundang': 'shinbundang_compact_256.png',
  '공항': 'airport_railroad_compact_256.png',
  'airport': 'airport_railroad_compact_256.png',
  '인천 1': 'incheon_1_compact_256.png',
  '인천1': 'incheon_1_compact_256.png',
  'incheon_1': 'incheon_1_compact_256.png',
  '인천 2': 'incheon_2_compact_256.png',
  '인천2': 'incheon_2_compact_256.png',
  'incheon_2': 'incheon_2_compact_256.png',
  '의정부': 'uijeongbu_lrt_compact_256.png',
  'uijeongbu': 'uijeongbu_lrt_compact_256.png',
  '우이신설': 'ui_sinseol_compact_256.png',
  'ui_sinseol': 'ui_sinseol_compact_256.png',
  '김포골드': 'gimpo_goldline_compact_256.png',
  'gimpo': 'gimpo_goldline_compact_256.png',
  '용인에버': 'everline_compact_256.png',
  '에버라인': 'everline_compact_256.png',
  'everline': 'everline_compact_256.png',
  '신림': 'sillim_compact_256.png',
  'sillim': 'sillim_compact_256.png',
  '경춘': 'gyeongchun_compact_256.png',
  'gyeongchun': 'gyeongchun_compact_256.png',
  '경강': 'gyeonggang_compact_256.png',
  'gyeonggang': 'gyeonggang_compact_256.png',
  '서해': 'seohae_compact_256.png',
  'seohae': 'seohae_compact_256.png',
  '대경': 'daegyeong_compact_256.png',
  'daegyeong': 'daegyeong_compact_256.png',
};

const _numberedStationLineBadgeAssetNames = <String>{
  'busan_1_compact_256.png',
  'busan_2_compact_256.png',
  'busan_3_compact_256.png',
  'busan_4_compact_256.png',
  'daegu_1_compact_256.png',
  'daegu_2_compact_256.png',
  'daegu_3_compact_256.png',
  'daejeon_1_compact_256.png',
  'gwangju_1_compact_256.png',
  'seoul_1_compact_256.png',
  'seoul_2_compact_256.png',
  'seoul_3_compact_256.png',
  'seoul_4_compact_256.png',
  'seoul_5_compact_256.png',
  'seoul_6_compact_256.png',
  'seoul_7_compact_256.png',
  'seoul_8_compact_256.png',
  'seoul_9_compact_256.png',
};

String? _bundledStationLineBadgeAssetName(String assetName) =>
    _numberedStationLineBadgeAssetNames.contains(assetName) ? assetName : null;

bool stationLineBadgeNeedsRoundedCorners(String assetPath) =>
    assetPath.contains('/busan_') || assetPath.contains('/donghae_');

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

bool _isBusanLine({required String id, required String name}) {
  final normalizedId = id.toLowerCase();
  return name.contains('부산') ||
      name.contains('부산김해') ||
      name.contains('동해') ||
      normalizedId.contains('busan') ||
      normalizedId.contains('humetro') ||
      normalizedId.contains('bgl') ||
      normalizedId.contains('donghae');
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

/// 카탈로그 색이 없을 때 노선 이름·식별자로 추정하는 노선색 단일 소스.
///
/// 화면별로 흩어져 있던 노선색 매핑을 이 한 곳으로 모은다. 실제 노선색은
/// 카탈로그 데이터([StationSearchLine.color])를 우선 사용하고, 값이 없을 때만
/// 이 폴백을 쓴다.
const _lineColorFallbacks = <String, String>{
  '1호선': '#0052A4',
  '2호선': '#00A84D',
  '3호선': '#EF7C1C',
  '4호선': '#00A5DE',
  '5호선': '#996CAC',
  '6호선': '#CD7C2F',
  '7호선': '#747F00',
  '8호선': '#E6186C',
  '9호선': '#BDB092',
  '경의중앙선': '#77C4A3',
  '수인분당선': '#F5A200',
  '신분당선': '#D4003B',
  '공항철도': '#0090D2',
};

/// 브랜드 액센트 폴백(노선 추정 실패 시).
const String stationLineFallbackBrandHex = '#006D77';

/// 노선 이름/식별자로 표준 노선색 hex를 찾는다. 매칭 실패 시 브랜드 액센트.
String fallbackLineColorHex({String? lineId, String? lineName}) {
  final name = lineName ?? '';
  final id = (lineId ?? '').toLowerCase();
  for (final entry in _lineColorFallbacks.entries) {
    final key = entry.key;
    if (name.contains(key)) {
      return entry.value;
    }
    final numeric = key.replaceAll('호선', '');
    if (numeric != key && numeric.isNotEmpty && id.contains(numeric)) {
      return entry.value;
    }
  }
  return stationLineFallbackBrandHex;
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
