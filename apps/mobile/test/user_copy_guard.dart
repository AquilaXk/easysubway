import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _forbiddenUserCopy = <String>[
  '실기기 QA',
  '데이터팩',
  '공공 API',
  '공식 파일',
  '관리자 검수',
  '현장 검증',
  '정보 신뢰도',
  '정적 추정',
  '측정값',
  '로그인 정보',
  '인증 정보',
  '계정 접근',
  '내부 이동 기준점',
  'routeSearchId',
  'UUID',
  'token',
  'OFFICIAL_',
  'ADMIN_VERIFIED',
  'local-user',
];

void expectNoForbiddenUserCopy(WidgetTester tester) {
  final visibleCopy = <String>{};
  for (final widget in tester.allWidgets) {
    switch (widget) {
      case Text(:final data, :final textSpan):
        visibleCopy.add(data ?? textSpan?.toPlainText() ?? '');
      case Tooltip(:final message):
        visibleCopy.add(message ?? '');
      case Semantics(:final properties):
        visibleCopy.addAll([
          properties.label ?? '',
          properties.value ?? '',
          properties.hint ?? '',
        ]);
    }
  }

  for (final copy in visibleCopy.where((copy) => copy.trim().isNotEmpty)) {
    for (final forbidden in _forbiddenUserCopy) {
      expect(copy, isNot(contains(forbidden)));
    }
    expect(
      copy,
      isNot(matches(RegExp(r'(^|[^A-Za-z])(?:edge|node)([^A-Za-z]|$)'))),
    );
  }
}
