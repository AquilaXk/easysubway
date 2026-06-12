# 쉬운 지하철

**쉬운 지하철(easysubway)**은 고령자, 유모차 이용자, 휠체어 이용자, 임산부, 일시적 부상자, 큰 짐을 든 승객이 계단과 이동 장벽을 피해서 도시철도를 이용할 수 있도록 돕는 Android/iOS 앱입니다.

핵심 메시지는 **빠른 길보다, 갈 수 있는 길을 먼저 안내합니다.** 입니다.

## Scope

- 전국 도시철도, 광역철도, 공항철도, GTX, 경전철을 서비스 범위에 포함합니다.
- 지역별 데이터 품질은 Level 1-4로 구분하고, 신뢰도와 마지막 갱신일을 숨기지 않습니다.
- 초기 현장 검증 지역은 상록수역입니다.

## Stack

- Mobile: Flutter, Dart, Riverpod, go_router, Dio, Drift
- Backend: Java, eGovFrame 5.0, Spring Boot 3.5, Spring MVC, Spring Security, Spring Batch
- Data: PostgreSQL, PostGIS, Redis
- Infra: Docker, Docker Compose, GitHub Actions
- Maps: Naver Map first, Kakao Map as a secondary candidate

## Workspace

- `apps/mobile/`: Flutter Android/iOS app
- `backend/`: eGovFrame/Spring Boot backend modules
- `infra/`: local runtime and deployment infrastructure
- `scripts/`: data import and local development utilities
- `tools/ci/`: repository and CI contract checks

## Workflow

Tracked work follows this order:

1. Create or confirm a GitHub issue.
2. Create a branch from `main`.
3. Implement the scoped work.
4. Open a pull request.
5. Wait for CI.
6. Check CodeRabbit review, or run Codex CLI code review if CodeRabbit cannot run.
7. Merge after review and CI are clear.
8. Confirm the deployment or CD status when the change affects deployment.

Tracked documents are limited to this root `README.md` and GitHub issue/PR templates under `.github/`. Product plans, agent briefs, handoff notes, and operational state are kept local.
