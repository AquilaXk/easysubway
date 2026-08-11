<!-- A등급: API, schema, data, security, deployment, artifact, release, CI workflow·계약 테스트·release gate 변경. -->

## 관련 이슈 / Related issue

Closes #

## 작업 배경 / Summary

- Problem:
- Outcome:

## 작업 내용 / Changes

-

## Scope

### Included

-

### Excluded

-

### Ownership / dependencies

- Accountable owner or plan:
- Required predecessor output:
- Concurrent work overlap: None

## Documentation impact

- 영향 resource ID 또는 `NONE`:
- resourceClass:
- documentationFamily:
- lifecycle/evidence 영향:

## 검증 / Verification

| Check | Result / Evidence |
| --- | --- |
| Focused RED → GREEN | |
| Affected integration | |
| Required CI | |
| Manual / production-like | Not required — reason: |
| Security / privacy / accessibility | Not applicable — reason: |

- 실행한 명령과 결과:

## 검증 증거

UI, 접근성, 수동 QA, 배포 확인이 필요한 항목은 증거 첨부, 링크, 또는 로컬 evidence 경로를 적습니다. 증거가 필요 없는 항목은 사유를 적습니다.

## Version impact

- [ ] no version change
- [ ] mobile patch
- [ ] mobile minor
- [ ] mobile major
- [ ] backend deploy only
- [ ] datapack release only
- [ ] route/realtime contract change
- [ ] DB migration change

## Route commercialization gate impact

- [ ] route-commercialization-gate.json 영향 없음
- [ ] route ETA accuracy, realtime coverage, accessibility regression, route v2 contract report를 갱신했다.
- [ ] 상용 경로/ETA claim을 추가하거나 변경하지 않는다.

## Route release readiness tracker impact

- [ ] route-release-readiness-tracker.json 영향 없음
- [ ] #1414 하위 release blocker issue 또는 production evidence 완료 조건을 갱신했다.
- [ ] 실시간/교통약자 길찾기 출시 준비 완료 claim을 추가하거나 변경하지 않는다.

### Version decision

- mobile versionName / versionCode:
- datapack version:
- route / realtime contract:
- backend identity:

## Not run

- Check: None
- Reason:
- Rerun owner / condition:

## 리뷰어 메모 / Review focus

- 리뷰어가 먼저 봐야 할 지점:

## 리스크 / Risk

- Level: High
- Main risk:
- Failure behavior:
- State mutation on failure:
- Fallback or degraded-success path introduced: No

## Rollout / Recovery

- Rollout or activation:
- Monitoring / success signal:
- Rollback or recovery:
- Data / config compatibility after rollback:

## 체크리스트 / Checklist

- [ ] PR 본문은 이 템플릿 섹션을 삭제하지 않고 모두 채웠다.
- [ ] 이슈 범위와 실제 diff가 일치하며 관련 없는 변경을 포함하지 않았다.
- [ ] 위험에 필요한 검증과 미실행 사유를 기록했다.
- [ ] CodeRabbit 리뷰를 확인했다.
- [ ] GitHub PR Review 객체가 있는지 확인했다. CodeRabbit status check만으로는 리뷰 완료로 보지 않는다.
- [ ] CodeRabbit 실행이 불가능하거나 PR Review 객체가 없으면 Codex CLI code review를 단일 PR review로 게시했다.
- [ ] 배포 영향이 있는 경우 CD 상태를 확인했다.
