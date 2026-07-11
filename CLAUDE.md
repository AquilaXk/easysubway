# easysubway 에이전트 작업 규약

## 타 서비스 직접 언급 금지 (공개물 전반)

이 저장소는 공개 저장소다. **이슈·PR·커밋 메시지·코드 주석·저장소에 커밋되는 문서에서 경쟁/타 서비스명을 직접 언급하지 않는다.**

- 금지 예: 특정 지하철/지도/내비 앱의 상호나 브랜드명, 그 앱의 고유 기능명·브랜드 색·로고를 직접 지칭하는 것.
- 대신 중립 표현을 쓴다: "국내 대표 지하철 앱", "국내 대표 지도·대중교통 앱", "참고 앱", "레퍼런스 앱", "상용 앱".
- 디자인·기능을 참고할 때도 **레이아웃 원리·컴포넌트 패턴·표준 규격** 같은 일반화된 표현으로 기술한다. 특정 서비스를 "그대로 따라 한다"는 서술을 남기지 않는다.
- 실기기 참고 캡처 등 구체 자료는 `docs/`(gitignore, 로컬 전용)에만 두고, 저장소에 커밋되는 산출물에는 중립 표현으로만 반영한다.

이유: 공개물에 특정 경쟁사를 직접 지목하면 법적·평판 리스크가 있고, 우리 목표는 무분별한 카피가 아니라 보편적 디자인 원리의 차용이다.

## PR·병합 규약 (에이전트 필수 절차)

PR 생성만 하고 멈추면 절차 위반이다. 아래 전부가 한 세트다.

1. **PR 본문 양식 절대 준수**: `.github/pull_request_template.md`의 등급 규칙대로 A등급(route/accessibility/mobile UX/backend API/DB migration/deploy/auth/security/datapack release/CI workflow·계약 테스트·release gate JSON 변경)은 `PULL_REQUEST_TEMPLATE/full.md`, B/C등급은 `short.md` 내용을 body에 직접 채운다 (gh CLI는 template 쿼리 미지원). 자유 양식 금지. 관련 이슈 칸 빈 칸 금지.
2. PR 생성 직후 `automerge` 라벨을 부착한다.
3. CI 전 체크가 green이 될 때까지 감시하고, 실패는 원인 수정·재push로 닫는다.
4. 코드리뷰 thread를 전부 대응(수정 또는 근거 답변)하고 해결한다.
5. automerge 큐는 GitHub PR Review 객체를 요구한다(merge-workflow 4단계). CodeRabbit 리뷰를 요청하고, 실패·율제한 시 독립 리뷰 경로(클로드 리뷰 기능 등)의 산출물을 **단일 PR review**로 게시한다. **에이전트가 자기 작업물을 스스로 평가해 리뷰를 작성하는 셀프 리뷰는 금지**다.
6. **폴백 리뷰 양식**: 폴백 리뷰는 **단일 PR review 하나**로 게시한다. `## <도구> fallback review` 제목 + `Source:` / `Repository visibility:` / `Fallback 사유:` / `확인 범위:` / `결과:` 불릿 필드 필수. 공개 저장소이므로 `Repository visibility: public GitHub repository`를 포함한다. 자유 양식 금지.
7. 리뷰 객체 확보 후 `automerge` 라벨을 재부착해 큐에 재진입시키고, **병합 확인까지**가 에이전트의 몫이다.
8. **closed/병합된 PR 본문은 사후 보정하지 않는다** (법적·보안·비밀 노출 수정 예외). 양식 guard는 PR 생성 시점에 적용한다. 이슈·PR 본문·리뷰 코멘트 서술은 전부 한국어로 작성한다 (코드 토큰·명령어·고정 섹션명 예외).
