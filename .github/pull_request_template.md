<!--
작업 등급에 맞는 템플릿을 사용하세요.
- A등급(제품/운영 위험 또는 CI workflow·계약 테스트·release gate 변경): .github/PULL_REQUEST_TEMPLATE/full.md 내용으로 교체합니다.
- B/C등급(일반 코드 변경·낮은 위험 maintenance): .github/PULL_REQUEST_TEMPLATE/short.md 내용으로 교체합니다.
- 웹 UI에서는 ?template=full.md 또는 ?template=short.md 쿼리를 쓸 수 있습니다. gh CLI는 template 쿼리를 지원하지 않으므로 템플릿 파일 내용을 body로 직접 채웁니다.
- 리뷰·automerge 게이트는 등급과 무관하게 모든 PR 공통입니다.
-->

## 관련 이슈 / Related issue

<!-- 단일 완결 PR은 `Closes #N`, 상위/중간 참조는 `Refs #N`, C등급 생략은 `이슈 없음(C등급)`으로 적습니다. -->
Refs #

## 작업 내용 / Summary

- Problem:
- Outcome:
- Changes:

## Scope

### Included

-

### Excluded

-

## Documentation impact

- 영향 resource ID 또는 `NONE`:
- resourceClass:
- documentationFamily:
- lifecycle/evidence 영향:

## 검증 / Verification

| Check | Result / Evidence |
| --- | --- |
| Focused test | |
| Required CI | |
| Manual / runtime | Not required — reason: |

- 실행한 명령과 결과:

## 영향 / Risk

- Level: Low / Medium / High
- Main risk:
- Compatibility or migration impact: None
- Failure behavior:
- Rollback or recovery:

## 체크리스트 / Checklist

- [ ] 작업 등급에 맞는 템플릿을 사용했다.
- [ ] 이슈 범위와 실제 diff가 일치하며 관련 없는 변경을 포함하지 않았다.
- [ ] 필요한 검증 결과와 미실행 사유를 기록했다.
- [ ] GitHub PR Review 객체가 있는지 확인했다. CodeRabbit status check만으로는 리뷰 완료로 보지 않는다.
