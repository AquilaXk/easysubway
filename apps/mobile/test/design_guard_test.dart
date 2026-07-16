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

  // radius 숫자 리터럴을 파싱해 상한(8) 초과 매치만 센다.
  // BorderRadius.circular(N) / Radius.circular(N) 에서 N > 8 인 경우만 위반.
  // (const 상한 8 = EasySubwayRadius 최대치. pill 방지 원칙 #1915)
  Map<String, int> countRoundingOverEight({Set<String> exclude = const {}}) {
    final pattern = RegExp(
      r'(?:BorderRadius|Radius)\.circular\(\s*([0-9.]+)\s*\)',
    );
    final counts = <String, int>{};
    sources.forEach((path, source) {
      if (exclude.any(path.endsWith)) {
        return;
      }
      var count = 0;
      for (final match in pattern.allMatches(source)) {
        final value = double.tryParse(match.group(1)!);
        if (value != null && value > 8) {
          count++;
        }
      }
      if (count > 0) {
        counts[path] = count;
      }
    });
    return counts;
  }

  // splashColor/highlightColor 가 지정됐지만 값이 Colors.transparent 가 아닌 경우,
  // 또는 splashFactory 에 InkSplash/InkRipple(리플 켜기)을 명시한 경우를 위반으로 센다.
  // (splashColor: Colors.transparent, splashFactory: NoSplash.splashFactory 는 통과)
  Map<String, int> countSplashViolations({Set<String> exclude = const {}}) {
    // 값이 Colors.transparent 로 끝나지 않는 splash/highlight 지정.
    // \S 로 잡아야 backtracking 으로 공백만 소비하는 오탐을 막는다
    // (splashColor: Colors.transparent 를 위반으로 잘못 세지 않도록).
    final tintedRipple = RegExp(
      r'(?:splashColor|highlightColor)\s*:\s*(?!Colors\.transparent\b)\S',
    );
    // 리플 팩토리를 명시적으로 켜는 경우 (NoSplash 는 제외).
    final rippleFactory = RegExp(r'\b(?:InkSplash|InkRipple)\.splashFactory\b');
    final counts = <String, int>{};
    sources.forEach((path, source) {
      if (exclude.any(path.endsWith)) {
        return;
      }
      final count =
          tintedRipple.allMatches(source).length +
          rippleFactory.allMatches(source).length;
      if (count > 0) {
        counts[path] = count;
      }
    });
    return counts;
  }

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
    expectRatchet(actual, const {}, rule: '로컬 색 상수');
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
      // 의도 잔존: 온보딩 시작·프리셋·권한 화면 타이틀 (#1936 전면 재설계로 축소)
      'lib/onboarding.dart': 4,
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
      'lib/features/notifications/presentation/notification_inbox_screen.dart':
          2,
      'lib/station_search.dart': 1,
      // 의도 잔존: 운행 공지 배너 — 운행 중단 상태 의미 (v4 허용 예외)
      'lib/features/service_notice/presentation/service_notice_banner.dart': 1,
    }, rule: '장식 Soft 틴트');
  });

  test('노선도 그림자/elevation 재유입 금지 가드 (#1933)', () {
    final filesToCheck = ['lib/network_map.dart', 'lib/route_search.dart'];
    final violations = <String, List<String>>{};

    for (final filePath in filesToCheck) {
      final source = sources[filePath];
      expect(source, isNotNull, reason: '$filePath 를 찾을 수 없다');

      // elevation: 뒤에 0(단어 경계)이 아닌 숫자가 오면 위반.
      final nonZeroElevation = RegExp(
        r'elevation:\s*(?!0\b)\d',
      ).allMatches(source!).length;
      final shadow = RegExp(
        r'shadowColor|BoxShadow|boxShadow',
      ).allMatches(source).length;

      final fileViolations = <String>[];
      if (nonZeroElevation > 0) {
        fileViolations.add('0 초과 elevation: $nonZeroElevation건');
      }
      if (shadow > 0) {
        fileViolations.add('shadowColor/BoxShadow: $shadow건');
      }

      if (fileViolations.isNotEmpty) {
        violations[filePath] = fileViolations;
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '그림자/elevation 재유입 금지 — border나 배경색으로만 '
          'depth를 표현하라 #1933\n'
          '${violations.entries.map((e) => '${e.key}: ${e.value.join(", ")}').join('\n')}',
    );
  });

  test(
    'showMenu/PopupMenuButton 재유입 금지 + showGeneralDialog 오버레이 elevation 가드 (#1933)',
    () {
      // (A) showMenu(...)·PopupMenuButton(...) 는 기본 elevation(그림자)을 강제하는
      //     오버레이 위젯이라 시각 언어 v4에서 재유입 자체를 금지한다. lib 전체 0건 유지.
      final menuOffenders = countPerFile(
        RegExp(r'\bshowMenu\(|\bPopupMenuButton\('),
      );
      expect(
        menuOffenders,
        isEmpty,
        reason:
            'showMenu(...)·PopupMenuButton(...) 는 기본 elevation(그림자)을 강제하므로 '
            '전면 금지다 — 커스텀 오버레이로 대체하라 (#1933). $menuOffenders',
      );

      // (B) showGeneralDialog 로 띄우는 오버레이는 Material 표면마다 elevation: 0 을
      //     명시해야 기본 elevation(그림자)이 조용히 재유입되지 않는다. showGeneralDialog
      //     사용 파일에서 Material( 호출 건수 <= elevation: 0 표기 건수 여야 통과.
      final overlayFiles = <String>[];
      sources.forEach((path, source) {
        if (RegExp(r'\bshowGeneralDialog\b').hasMatch(source)) {
          overlayFiles.add(path);
        }
      });
      expect(overlayFiles, isNotEmpty, reason: 'showGeneralDialog 사용 파일이 없다');

      final materialPattern = RegExp(r'\bMaterial\(');
      final elevationZeroPattern = RegExp(r'elevation:\s*0(?![\d.])');

      final violations = <String>[];
      for (final filePath in overlayFiles) {
        final source = sources[filePath]!;
        final materialCount = countIn(source, materialPattern);
        final elevationZeroCount = countIn(source, elevationZeroPattern);

        if (materialCount > elevationZeroCount) {
          violations.add(
            '$filePath: Material( 호출 $materialCount건, '
            'elevation: 0 명시 $elevationZeroCount건',
          );
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'showGeneralDialog 오버레이의 Material 표면은 매번 elevation: 0 을 명시해야 '
            '한다 — 그렇지 않으면 Flutter 기본 elevation으로 그림자가 조용히 '
            '재유입된다 (#1933).\n'
            '${violations.join('\n')}',
      );
    },
  );

  test('StadiumBorder ratchet — pill 형태 제거 대상 (0으로 수렴)', () {
    // pill(stadium) 형태는 각진 사각형(radius <= 8) 원칙 위반이다.
    // 완전한 원이 필요하면 CircleBorder 를 쓴다. 상한은 내리기만 한다.
    // TODO: 아래 잔존을 RoundedRectangleBorder(radius <= 8)로 전환 후 하드 밴으로.
    final actual = countPerFile(RegExp(r'\bStadiumBorder\b'));
    expectRatchet(actual, const {}, rule: 'StadiumBorder(pill)');
  });

  test('BorderRadius.circular(999) 등 캡슐형 큰 radius ratchet — 0으로 수렴', () {
    // 사실상 pill 을 만드는 관용적 초대형 radius(>= 100)는 원(圓) 의도가 아니라
    // 캡슐(pill) 의도이므로 제거 대상. 완전한 원은 CircleBorder 로 표현한다.
    // 상한은 내리기만 한다.
    // TODO: 아래 잔존을 각진 사각형으로 전환 후 하드 밴(0건)으로 전환.
    final pattern = RegExp(
      r'(?:BorderRadius|Radius)\.circular\(\s*([0-9.]+)\s*\)',
    );
    final actual = <String, int>{};
    sources.forEach((path, source) {
      var count = 0;
      for (final match in pattern.allMatches(source)) {
        final value = double.tryParse(match.group(1)!);
        if (value != null && value >= 100) {
          count++;
        }
      }
      if (count > 0) {
        actual[path] = count;
      }
    });
    expectRatchet(actual, const {}, rule: '캡슐형 초대형 radius(>= 100)');
  });

  test('과한 라운딩 ratchet — radius <= 8 로 수렴 (pill 금지)', () {
    // BorderRadius.circular(N)/Radius.circular(N) 에서 N > 8 인 사용처.
    // 원칙: 각진 사각형, radius <= 8. 상한은 내리기만 한다.
    // 예외 없음(0으로 수렴 대상): network_map 노드 점 등 완전한 원은
    // CircleBorder 로 표현하므로 이 매치에 잡히지 않는다.
    final actual = countRoundingOverEight(
      exclude: {'accessible_design.dart', 'design_tokens.dart'},
    );
    expectRatchet(actual, {
      // 의도 잔존: 역 상세 정보/도움/시설 카드·액션 버튼 radius (16/12) — 무박스 전환 진행 중
      'lib/station_search.dart': 4,
      // 의도 잔존: AppCard(20)·공용 control radius(12) — v4 정리 대상
      'lib/app/app_components.dart': 2,
      // 의도 잔존: 앱 shell 입력 필드(12) — v4 정리 대상
      'lib/app/easy_subway_app.dart': 1,
      // 의도 잔존: 홈 알림 control radius(12) — v4 정리 대상
      'lib/features/home/presentation/home_screen.dart': 1,
      // 의도 잔존: 노선 선택 헤더 캡슐(13)·역명 배지(24) — 노선도 룩 불변, 완전 원 아님
      'lib/network_map.dart': 2,
      // 의도 잔존: 시설 신고 카드 radius(16) — 무박스 전환 대상
      'lib/facility_report.dart': 1,
      // 의도 잔존: 알림 설정 카드 radius(16) — 무박스 전환 대상
      'lib/notification_settings.dart': 1,
      // 의도 잔존: 운행 공지 리스트 카드 radius(12) — 무박스 전환 대상
      'lib/features/service_notice/presentation/service_notice_list_screen.dart':
          1,
      // 의도 잔존: 운행 공지 배너 radius(14) — 운행 상태 배너 룩
      'lib/features/service_notice/presentation/service_notice_banner.dart': 1,
    }, rule: '과한 라운딩(radius > 8)');
  });

  test('블록(박스) Card ratchet — 행+구분선 레이아웃으로 수렴', () {
    // Card 위젯은 블록(박스) 레이아웃의 원천. 원칙은 행 + 구분선 + 여백이다.
    // 이미 무박스로 정리된 화면(onboarding·network_map)은 0으로 고정된다.
    // 상한은 내리기만 한다.
    final actual = countPerFile(RegExp(r'\bCard\('));
    expectRatchet(actual, {
      // 의도 잔존: 역 상세 카드 1곳 — 무박스(행+구분선) 전환 진행 중
      'lib/station_search.dart': 1,
      // 동일 총량 중 출구 카드 1곳은 canonical presentation 경로로 이동했다.
      'lib/features/stations/presentation/station_exit_card.dart': 1,
      // 동일 총량 중 시설 상세 카드 1곳은 canonical presentation 경로로 이동했다.
      'lib/features/stations/presentation/station_facility_detail_screen.dart':
          1,
      // 동일 총량 중 시설 목록 카드 1곳은 canonical presentation 경로로 이동했다.
      'lib/features/stations/presentation/station_facility_card.dart': 1,
      // 안내 확인 방법 카드는 두 화면이 공유하는 canonical component로 이동했다.
      'lib/features/stations/presentation/station_info_basis_disclosure.dart':
          1,
      // 동일 총량 중 주변 역 검색 카드 1곳은 canonical presentation 경로로 이동했다.
      'lib/features/stations/presentation/station_search_body.dart': 1,
      // 의도 잔존: AppCard 공용 래퍼·정보 카드 2곳 — 무박스 전환 대상
      'lib/app/app_components.dart': 2,
    }, rule: '블록(박스) Card');
  });

  test('탭 splash/highlight 하드 밴 — 리플 재유입 금지 (0건 유지)', () {
    // splashColor/highlightColor 가 Colors.transparent 가 아니거나,
    // InkSplash/InkRipple 팩토리를 명시하면 위반.
    // (Colors.transparent, NoSplash.splashFactory 는 통과 — 리플을 끈 것)
    final offenders = countSplashViolations();
    expect(
      offenders,
      isEmpty,
      reason:
          '탭 splash/highlight(리플) 금지 — 무채색·무장식 원칙. '
          'splashColor/highlightColor 는 Colors.transparent 로, '
          'splashFactory 는 NoSplash.splashFactory 로 끄라 (#1915). $offenders',
    );
  });
}
