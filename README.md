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

## Production Configuration

운영 배포는 `prod` profile을 기준으로 아래 환경변수를 설정해야 합니다.

| Name | Required | Description |
| --- | --- | --- |
| `EASYSUBWAY_DATASOURCE_URL` | Yes | PostgreSQL JDBC URL |
| `EASYSUBWAY_DATASOURCE_USERNAME` | Yes | PostgreSQL 계정 |
| `EASYSUBWAY_DATASOURCE_PASSWORD` | Yes | PostgreSQL 비밀번호 |
| `EASYSUBWAY_REDIS_HOST` | Yes | 익명 인증 발급 제한에 사용할 Redis host |
| `EASYSUBWAY_REDIS_PORT` | No | Redis port. 기본값은 `6379`입니다. |
| `EASYSUBWAY_TRUSTED_PROXY_CIDRS` | Yes | `X-Forwarded-For`를 신뢰할 프록시 IP 또는 CIDR 목록입니다. 예: `10.0.0.0/8,192.168.0.10` |

`EASYSUBWAY_TRUSTED_PROXY_CIDRS`는 ALB, Nginx, API Gateway처럼 애플리케이션 앞단에 있는 신뢰 가능한 프록시만 포함해야 합니다. 운영에서는 누락 시 시작 단계에서 설정 오류가 드러나도록 기본값을 두지 않습니다. 개발 환경은 프록시 없이도 로컬 실행할 수 있도록 빈 기본값을 허용하며, 이 경우 전달 헤더를 익명 인증 발급 제한 키로 사용하지 않습니다.

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
