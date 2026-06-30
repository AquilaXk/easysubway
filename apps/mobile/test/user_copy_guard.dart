import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _forbiddenUserCopy = <String>[
  '실기기 QA',
  '데이터팩',
  '개인정보 및 데이터',
  '공공 API',
  '공식 파일',
  '관리자 검수',
  '현장 검증',
  '정보 신뢰도',
  '높은 신뢰도',
  '보통 신뢰도',
  '낮은 신뢰도',
  '기본정보',
  '기본 정보',
  '기본 정보만 있음',
  '정보 부족',
  '부족해요',
  '정보가 부족해요',
  '상태 정보가 부족해요',
  '정보만',
  '한 번 더 확인',
  '확인이 더 필요',
  '상세 이동 정보',
  '상세 정보',
  '상세정보',
  '기본 데이터',
  '데이터 품질',
  '확인 수준',
  '확인 필요',
  '확인이 필요',
  '확인 요청',
  '정보 확인 필요',
  '상태 확인 필요',
  '현장 확인 필요',
  '현장 위치 확인',
  '노선 정보 없음',
  '살펴볼 시설 없음',
  '다시 볼 시설 없음',
  '환승 없음',
  '삭제할 항목 없음',
  '계단 없음 확인',
  '새 알림 없음',
  '현재 이용할 수 없음',
  '위치 확인 필요',
  '이용 불가 확인',
  '심각도',
  '다음 행동',
  '권장 행동',
  '기준:',
  '현재 위치 기준',
  '선택한 경로 기준',
  '길 안내 기준',
  '좌표 기준',
  '출처',
  '점검·제보',
  '취약점',
  '검수 완료',
  '제보 필요',
  '추정',
  '정적 추정',
  '측정값',
  '로그인 정보',
  '인증 정보',
  '계정 접근',
  '서버에서',
  '익명화',
  '법적·보안상',
  '제보 처리',
  '처리 절차',
  '처리 결과',
  '처리 상태',
  '처리하지 못했어요',
  '처리 완료',
  '개인을 알 수 없게 처리',
  '임시 설정',
  '제보 연결 정보',
  '경로 의견 연결 정보',
  '개인정보 제거',
  '출구 정보가 아직 없습니다',
  '시설 정보가 아직 없습니다',
  '내부 이동 기준점',
  '기준점',
  '이동 점수',
  '이동 편의도',
  '이동 구조',
  '점수',
  '최근 확인됨',
  '우선 적용',
  '기본 적용',
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
    expect(copy, isNot(matches(RegExp(r'\d+\s*점'))));
  }
}
