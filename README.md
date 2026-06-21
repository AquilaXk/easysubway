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
- Data: PostgreSQL, PostGIS
- Infra: Docker, Docker Compose, GitHub Actions
- Maps: Naver Map first, Kakao Map as a secondary candidate

## Runtime Environment

`.env.example`은 로컬 실행과 배포에 필요한 dotenv 양식입니다. 실제 값은 git에 올리지 않는 로컬 `.env`에만 둡니다.

GitHub Actions에는 개별 환경변수를 여러 개 만들지 않고, 로컬 `.env` 파일 전체를 `EASYSUBWAY_ENV` secret 하나로 저장합니다. GitHub Actions secret 이름은 반드시 `EASYSUBWAY_ENV`만 사용합니다.

```bash
scripts/github/sync-actions-env-secret.sh .env
```

워크플로에서 실제 배포 값을 사용할 때는 `secrets.EASYSUBWAY_ENV`를 파일로 복원한 뒤 그 파일을 `docker compose --env-file` 또는 애플리케이션 실행 환경에 넘깁니다. PR CI는 민감값이 필요하지 않으므로 `.env.example`로 양식만 검증합니다.

CD workflow는 `EASYSUBWAY_ENV` secret이 있으면 배포 dotenv 계약을 검증하고, 아직 secret이 없으면 `.env.example`로 배포 설정 양식만 확인합니다.

`EASYSUBWAY_TRUSTED_PROXY_CIDRS`는 ALB, Nginx, API Gateway처럼 애플리케이션 앞단에 있는 신뢰 가능한 프록시 IP 또는 CIDR 목록입니다. 예: `10.0.0.0/8,192.168.0.10`. 운영에서는 누락 시 시작 단계에서 설정 오류가 드러나도록 기본값을 두지 않습니다. 개발 환경은 프록시 없이도 로컬 실행할 수 있도록 빈 기본값을 허용하며, 이 경우 전달 헤더를 익명 인증 발급 제한 키로 사용하지 않습니다.

운영 프로필은 관리자 화면과 API를 열 수 있는 계정이 반드시 필요합니다. `EASYSUBWAY_ADMIN_USERNAME`과 `EASYSUBWAY_ADMIN_PASSWORD`가 비어 있으면 백엔드가 시작되지 않습니다.

모바일 앱의 도움말 화면은 개인정보처리방침, 고객지원, 보안 문의, 데이터 삭제 요청 경로를 `dart-define`으로 받습니다. 릴리즈 빌드는 아래 값이 비어 있으면 시작 단계에서 실패하며, 개인정보처리방침은 HTTPS URL, 나머지는 메일 주소 형식이어야 합니다. 릴리즈 빌드 전 로컬 `.env`와 GitHub Actions `EASYSUBWAY_ENV`에 값을 맞춘 뒤 Flutter 빌드 명령에 전달합니다.

- `EASYSUBWAY_PRIVACY_POLICY_URL`
- `EASYSUBWAY_SUPPORT_EMAIL`
- `EASYSUBWAY_SECURITY_EMAIL`
- `EASYSUBWAY_DATA_DELETION_EMAIL`

푸시 알림은 실제 FCM/APNs 공급자와 기기 QA가 끝나기 전까지 릴리즈 기본 범위에서 제외합니다. 알림 설정 화면과 저장소 연동을 테스트할 때만 `--dart-define=EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS=true`를 명시하고, 기본값은 `.env.example`처럼 `false`로 유지합니다.

## Mobile Data

사용자 로컬 DB는 즐겨찾기, 최근 검색, 신고 receipt처럼 사용자가 만든 데이터를 보관합니다. 앱 업데이트로 schema가 바뀔 때는 Drift `MigrationStrategy.onUpgrade`에 단계별 migration을 추가하고, v1 fixture에서 현재 schema로 열었을 때 사용자 데이터가 유지되는 테스트를 먼저 갱신합니다.

Migration 실패를 무시하고 DB를 삭제하거나 재생성하지 않습니다. 복구가 필요한 변경은 사용자 데이터 보존 범위, 실패 시 차단 동작, 롤백 가능 여부를 코드와 테스트로 먼저 고정한 뒤 릴리즈합니다.

## Workspace

- `apps/mobile/`: Flutter Android/iOS app
- `backend/`: eGovFrame/Spring Boot backend modules
- `infra/`: local runtime and deployment infrastructure
- `scripts/`: data import and local development utilities
- `tools/ci/`: repository and CI contract checks

## Operations

운영 관측성과 알림 기준선은 `apps/mobile/release/operations-observability-gate.json`을 기준으로 검증합니다. 이 gate는 release blocker이며, PR에서는 `node --test tools/ci/*.test.mjs`로 필수 신호와 artifact 보관 계약을 확인합니다.

필수 운영 신호 ID:

- `backend_health_readiness_storage_datapack_report`
- `report_api_error_rate`
- `admin_review_latency`
- `datapack_release_publish_result`
- `mobile_crash_free_rate`
- `mobile_anr_rate`
- `mobile_app_start_failure_rate`
- `route_search_found_blocked_unknown_distribution`
- `datapack_install_rollback_failure_rate`
- `realtime_provider_success_stale_timeout_latency_eta_error`
- `report_upload_failure_duplicate_orphan_cleanup_rate`
- `cross_version_correlation_ids`
- `android_mapping_retention`
- `ios_dsym_retention`

운영 로그와 artifact에는 receipt token, upload URL, photo metadata를 남기지 않습니다. 장애 증거에는 app version, datapack version, route engine version, provider snapshot id를 함께 기록해야 하며, 외부 provider나 store console이 필요한 신호는 PR 검증 증거에 외부 차단 조건과 남은 리스크를 기록합니다.

백업과 복구 리허설 기준선은 `apps/mobile/release/backup-restore-rehearsal-gate.json`으로 검증합니다. PR과 릴리즈 후보에서는 `node tools/ops/backup-restore-rehearsal-check.mjs`로 PostgreSQL dump, 신고 사진 object manifest, 데이터팩 source inventory, 데이터팩 release manifest history가 모두 복구 리허설 대상에 포함되는지 확인합니다. 실제 database dump, 사진 object, signed URL, credential, receipt token은 GitHub에 올리지 않고 `.codex/evidence/backup-restore-rehearsal/<date>/` 아래 로컬 전용 증거로만 보관합니다.

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
