import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1915 시각 언어 v4 재발 방지 ratchet 가드.
///
/// 규칙: 상한은 내리기만 한다. 이 테스트가 빨간불이면 상한을 올리지 말고
/// 사용처를 공용 토큰(design_tokens.dart)·중립 표면·구분선으로 정리하라.
/// 최종 목표: 로컬 색 상수 0, w900 0, w800 = 화면 타이틀 수, Gradient 0,
/// 장식 Soft 틴트 0.
void main() {
  final libDir = Directory('lib');
  late final Map<String, String> sources;

  setUpAll(() {
    sources = <String, String>{};
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        sources[entity.path] = entity.readAsStringSync();
      }
    }
  });

  int countIn(String source, Pattern pattern) =>
      pattern.allMatches(source).length;

  Map<String, int> countPerFile(
    Pattern pattern, {
    Set<String> exclude = const {},
  }) {
    final counts = <String, int>{};
    sources.forEach((path, source) {
      if (exclude.any(path.endsWith)) {
        return;
      }
      final count = countIn(source, pattern);
      if (count > 0) {
        counts[path] = count;
      }
    });
    return counts;
  }

  void expectRatchet(
    Map<String, int> actual,
    Map<String, int> max, {
    required String rule,
  }) {
    final violations = <String>[];
    actual.forEach((path, count) {
      final limit = max[path] ?? 0;
      if (count > limit) {
        violations.add('$path: $count건 (상한 $limit)');
      }
    });
    expect(
      violations,
      isEmpty,
      reason:
          '[$rule] 상한 초과. 상한을 올리지 말고 사용처를 토큰·중립 표면으로 정리하라 (#1915).\n'
          '${violations.join('\n')}',
    );
  }

  test('그라데이션 하드 밴 — 0건 유지', () {
    final offenders = countPerFile(
      RegExp(r'\bLinearGradient\b|\bRadialGradient\b|\bSweepGradient\b'),
    );
    expect(
      offenders,
      isEmpty,
      reason: '그라데이션은 전면 금지다 (#1915 금지 목록, #1438 전례). $offenders',
    );
  });

  test('화면 로컬 색 상수 ratchet — 공용 토큰으로 수렴', () {
    final actual = countPerFile(
      RegExp(r'^const _\w*Color\b\s*=', multiLine: true),
      exclude: {'accessible_design.dart', 'design_tokens.dart'},
    );
    expectRatchet(actual, {'lib/main.dart': 8}, rule: '로컬 색 상수');
  });

  test('FontWeight.w900 ratchet — 전면 제거 대상', () {
    final actual = countPerFile(RegExp(r'FontWeight\.w900'));
    expectRatchet(actual, const {}, rule: 'w900');
  });

  test('FontWeight.w800 ratchet — 화면 타이틀 한정', () {
    final actual = countPerFile(
      RegExp(r'FontWeight\.w800'),
      exclude: {'accessible_design.dart', 'design_tokens.dart'},
    );
    expectRatchet(actual, {
      // 의도 잔존: 기준 화면(노선도 홈·좌측 메뉴) — 룩 불변 원칙
      'lib/network_map.dart': 8,
      // 의도 잔존: 온보딩 스플래시·페이지 타이틀 (w900은 w800로 강등)
      'lib/onboarding.dart': 6,
      // 의도 잔존: 노선 배지 번호 — 색 배지 위 시인성 (w900은 w800로 강등)
      'lib/features/stations/presentation/station_line_badges.dart': 2,
    }, rule: 'w800');
  });

  test('장식 Soft 틴트 ratchet — 상태 의미 없는 배경 틴트 제거', () {
    final actual = countPerFile(
      RegExp(r'\b(?:mintSoft|skySoft|redSoft|amberSoft)\b'),
      exclude: {'accessible_design.dart', 'design_tokens.dart'},
    );
    expectRatchet(actual, {
      // 의도 잔존: 시설 상태 카드 blocked/caution — 상태 의미 틴트 (v4 허용 예외)
      'lib/main.dart': 2,
      'lib/station_search.dart': 1,
      // 의도 잔존: 운행 공지 배너 — 운행 중단 상태 의미 (v4 허용 예외)
      'lib/features/service_notice/presentation/service_notice_banner.dart': 1,
    }, rule: '장식 Soft 틴트');
  });
}
