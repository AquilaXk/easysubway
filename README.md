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

GitHub Actions에는 애플리케이션 환경값을 개별 환경변수로 여러 개 만들지 않고, 로컬 `.env` 파일 전체를 `EASYSUBWAY_ENV` secret 하나로 저장합니다. 애플리케이션 환경값용 GitHub Actions secret 이름은 반드시 `EASYSUBWAY_ENV`만 사용합니다.

```bash
scripts/github/sync-actions-env-secret.sh .env
```

워크플로에서 실제 배포 값을 사용할 때는 `secrets.EASYSUBWAY_ENV`를 파일로 복원한 뒤 그 파일을 `docker compose --env-file` 또는 애플리케이션 실행 환경에 넘깁니다. PR CI는 민감값이 필요하지 않으므로 `.env.example`로 양식만 검증합니다.

CD workflow는 `EASYSUBWAY_ENV` secret이 있으면 배포 dotenv 계약을 검증하고 Compose env와 backend env로 분리합니다. 아직 secret이나 SSH 접속 정보가 없으면 bootJar와 설정 검증까지만 수행하고, 원격 배포는 `not_started`로 기록합니다.

운영 SSH 배포에는 애플리케이션 환경값과 별개로 production environment에 아래 값을 둡니다.

- Secrets: `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_PRIVATE_KEY`
- Variables: `DEPLOY_ROOT`, `DEPLOY_COMPOSE_PROJECT`, 선택 값 `DEPLOY_PUBLIC_API_BASE_URL`

CD는 `main`의 CI가 성공한 뒤 `workflow_run`으로 자동 실행됩니다. 수동 실행은 대상 SHA가 `main`에 있고 해당 SHA의 CI 성공 기록이 있을 때만 배포할 수 있습니다. `preflight` 모드는 dotenv 검증, Compose config, backend bootJar 생성까지만 확인합니다.

`EASYSUBWAY_OBJECT_STORAGE_ENDPOINT`는 data pack publish용 공개 S3 endpoint 계약을 유지합니다. backend report 사진 저장소가 Compose 내부 MinIO에 붙을 때는 `EASYSUBWAY_REPORT_OBJECT_STORAGE_INTERNAL_ENDPOINT=http://object-storage:9000`을 별도로 설정합니다.

`EASYSUBWAY_TRUSTED_PROXY_CIDRS`는 ALB, Nginx, API Gateway처럼 애플리케이션 앞단에 있는 신뢰 가능한 프록시 IP 또는 CIDR 목록입니다. 예: `10.0.0.0/8,192.168.0.10`. 운영에서는 누락 시 시작 단계에서 설정 오류가 드러나도록 기본값을 두지 않습니다. 개발 환경은 프록시 없이도 로컬 실행할 수 있도록 빈 기본값을 허용하며, 이 경우 전달 헤더를 익명 인증 발급 제한 키로 사용하지 않습니다.

운영 프로필은 관리자 화면과 API를 열 수 있는 계정이 반드시 필요합니다. `EASYSUBWAY_ADMIN_USERNAME`과 `EASYSUBWAY_ADMIN_PASSWORD`가 비어 있으면 백엔드가 시작되지 않습니다.

모바일 앱의 도움말 화면은 개인정보처리방침, 고객지원, 보안 문의, 데이터 삭제 요청 경로를 `dart-define`으로 받습니다. 릴리즈 빌드는 아래 값이 비어 있으면 시작 단계에서 실패하며, 개인정보처리방침은 HTTPS URL, 나머지는 메일 주소 형식이어야 합니다. 릴리즈 빌드 전 로컬 `.env`와 GitHub Actions `EASYSUBWAY_ENV`에 값을 맞춘 뒤 Flutter 빌드 명령에 전달합니다.

- `EASYSUBWAY_PRIVACY_POLICY_URL`
- `EASYSUBWAY_SUPPORT_EMAIL`
- `EASYSUBWAY_SECURITY_EMAIL`
- `EASYSUBWAY_DATA_DELETION_EMAIL`

푸시 알림은 실제 FCM/APNs 공급자와 기기 QA가 끝나기 전까지 릴리즈 기본 범위에서 제외합니다. 알림 설정 화면과 저장소 연동을 테스트할 때만 `--dart-define=EASYSUBWAY_ENABLE_PUSH_NOTIFICATIONS=true`를 명시하고, 기본값은 `.env.example`처럼 `false`로 유지합니다.

모바일 signed release artifact gate는 `apps/mobile/release/signed-release-artifact-gate.json`으로 검증합니다. Android-first 배포 파이프라인은 Android AAB와 backend image만 생성하며, CI의 Android AAB는 임시 self-signed keystore로 생성하므로 store-ready가 아닙니다. iOS artifact와 dSYM 보관은 iOS 출시 준비 단계까지 deferred 상태로 두고 현재 workflow에서는 생성하지 않습니다. Android 제출 준비 상태는 Android 15 (API 35) target requirement, production signing key material, Play App Signing, Play internal track 업로드 또는 pre-launch report 증거가 있어야 합니다. Android RC와 Google Play 제출 증거는 `apps/mobile/release/android-rc-store-evidence.json` 계약에 맞춰 Play-generated APK 또는 Play-installed build smoke, 16 KB page-size, TalkBack/큰 글씨/작은 화면, Data Safety/network trace, pre-review/pre-launch 결과를 수집합니다. iOS 제출 증거는 Android Google Play v1 release blocker가 아니며 future iOS release gate로 deferred 상태이고, 그때 Xcode 26, Apple distribution signing, TestFlight, dSYM 90일 보관 workflow를 다시 확인합니다. 민감한 설치/스토어 콘솔 증거는 GitHub에 파일로 올리지 않고 `.codex/evidence/release/mobile-signed-artifacts/` 또는 `.codex/evidence/release/android-rc-store/<rc-or-run>/` 아래 로컬 전용 경로에 보관한 뒤 PR에는 요약만 남깁니다.

Android 16 KB page-size gate는 `apps/mobile/release/android-16kb-page-size-gate.json`으로 검증합니다. AAB evidence는 `tools/mobile/check-android-aab-16kb-page-size.sh`로 bundletool config와 native `.so` LOAD segment alignment를 확인하고, runtime evidence는 `tools/mobile/run-android-16kb-page-size-smoke.sh`로 로컬 Android emulator의 `adb shell getconf PAGE_SIZE` 출력이 `16384`인지 먼저 확인합니다. 현재 로컬 emulator가 4 KB page-size이면 Go evidence로 쓰지 않고 16 KB system image 또는 Play-installed build 증거를 다시 수집합니다.

Google Play production access와 신규 personal account closed test gate는 `apps/mobile/release/play-production-access-gate.json`으로 검증합니다. 2023-11-13 이후 생성된 personal developer account라면 production access 신청 전 closed test 12명 이상, 14일 연속 opt-in, tester feedback/issue response, production readiness 답변과 승인 결과를 local-only evidence로 보관해야 합니다. 조직 계정이거나 기존 personal account라 closed test requirement가 적용되지 않더라도 Play Console account type, creation date, identity verification, Console 권한, 2단계 인증, production access 상태 summary는 release blocker 증거로 남깁니다.

Google Play App Content, Data Safety, 한국어 listing gate는 `apps/mobile/release/play-store-submission-content.json`으로 검증합니다. Data Safety 답변은 `apps/mobile/release/store-privacy-inventory.json`의 수집 데이터, 암호화 전송, 삭제 지원, 제3자 공유 없음, tracking 없음 값과 일치해야 하며 listing은 데이터 기준일, 지원 지역, 실시간 지원 범위, 확인 필요 상태를 명시합니다. “반드시 이동 가능”, “100% 안전”, “모든 역 완벽 지원”, “실시간 위치 정확”, “휠체어 경로 보장” 같은 보장 표현은 store copy와 screenshot 설명에서 사용할 수 없습니다.

Play-generated APK와 device compatibility matrix gate는 `apps/mobile/release/play-generated-apk-device-matrix-gate.json`으로 검증합니다. 로컬 AAB만으로는 Go evidence가 될 수 없고 Internal App Sharing, internal/closed testing, App Bundle Explorer generated APK, Play-installed build 중 하나로 설치한 뒤 split APK manifest, Play App Signing certificate, permission/network security config, Android 15/16, 16 KB page-size, 작은 화면, 큰 글씨, TalkBack, network block, low storage, low memory/process death smoke summary를 남겨야 합니다.

Android 출시 후 2시간/24시간/7일/30일 운영 검토는 `apps/mobile/release/post-launch-operations-review-gate.json`으로 검증합니다. Play review, crash/ANR, 지원 문의, 데이터 오류, provider quota, 신고 backlog, data-pack adoption 신호와 backend/datapack/realtime kill switch owner를 확인해야 하며, P0 앱 문제는 최초 공개에서는 staged rollout halt 대신 새 versionCode의 fixed release로 제출합니다. fixed release regression 증거는 실기기 대신 로컬 Android emulator에서 수집하고 민감한 Console, support, provider 증거는 `.codex/evidence/release/post-launch-operations-review/<rc-or-run>/` 아래 local-only summary로 보관합니다.

Android 출시 100% 범위와 Go/No-Go 계약은 `apps/mobile/release/release-governance-gate.json`으로 검증합니다. 이번 release blocker는 Android Google Play v1이며 iOS는 `DEFERRED_OUT_OF_SCOPE`로 기록해 Android 출시 완료를 차단하지 않습니다. open Android P0가 있거나 RC evidence의 git SHA, AAB hash, backend artifact, data pack manifest, route/realtime contract가 서로 맞지 않으면 최종 Go 판단을 하지 않습니다.

Android 출시 UX·접근성·성능 gate는 `apps/mobile/release/android-release-quality-gate.json`으로 검증합니다. PR 증거는 local Android emulator evidence를 우선 사용하며, 물리 기기 증거는 Codex PR 증거로 사용하지 않습니다. 실제 Google Play Go 판단 전에는 #907의 exact RC 또는 Play-installed build에서 TalkBack, 150%/200% 글자 크기, 작은 화면, 권한/네트워크/업로드 오류 복구, 노선도 fallback과 성능, 지원 범위/출처 화면, crash/ANR privacy-safe reporting 증거를 다시 수집해야 합니다.

## Privacy Policy

EasySubway collects and stores only the data needed to provide subway accessibility guidance, local route search, favorites, app settings, diagnostics, and facility report submission.

The mobile app can process location, station or route searches, accessibility preferences, report text, report photos, report receipt metadata, crash logs, and performance diagnostics for app functionality. Report photos and report text are used only for facility report review and are not used for advertising. EasySubway does not sell personal or sensitive user data.

Data is transmitted over HTTPS when network submission is required. Local favorites, recent searches, report receipts, drafts, preferences, and installed data-pack audit records remain on the user's device unless the user submits a report or requests deletion. Users can request deletion of report data or ask privacy questions through `privacy@easysubway.app`.

Store submission and release contact points:

- Privacy policy URL: `https://github.com/AquilaXk/easysubway#privacy-policy`
- Support: `support@easysubway.app`
- Security: `security@easysubway.app`
- Data deletion and privacy requests: `privacy@easysubway.app`

## Runtime Architecture

The local-first mobile runtime is the default user path. Station search, route search, station details, favorites, report receipt recovery, and accessibility copy must read installed data packs and the user database before any network fallback. A missing API base URL must not stop local database-backed startup.

The backend control-plane runtime is kept for report intake, report review, admin/operator pages, data-pack source control, and release operations. Removed mobile station, route, account, profile, notification, and favorite APIs must not become required for ordinary app launch or offline route guidance.

eGovFrame은 backend control-plane에만 선택 적용한다. 현재 production 허용 영역은 admin/operator pagination, data collection batch control-plane, 운영 logging/property/id 후보 검증이며, Flutter mobile runtime, ordinary mobile API, realtime hot path, token/crypto boundary, domain/application/public JSON contracts에는 eGovFrame type이나 starter를 흘리지 않는다. 이 기준은 `backend/quality/egovframe-control-plane-gate.json`과 repository contract test로 검증한다.

The receipt-token report boundary lets a user check or confirm a submitted report without an account. The plain receipt token is issued once, stored on the device, and must not be logged, returned again, or used in URLs after issuance; the backend stores only a peppered hash.

The data-pack pointer contract is atomic: an installed pack becomes current only after size, hash, gzip, SQLite quick check, schema, table, and production signature validation. Failed updates keep the previous `current.json` pointer and preserve user-owned data.

The user-data preservation contract separates replaceable catalog data from user-owned rows. Catalog pack swaps may replace station, route, facility, and data-quality records, but must not delete favorites, recent searches, report receipts, drafts, app preferences, or installed-pack audit rows.

## Mobile Data

사용자 로컬 DB는 즐겨찾기, 최근 검색, 신고 receipt처럼 사용자가 만든 데이터를 보관합니다. 앱 업데이트로 schema가 바뀔 때는 Drift `MigrationStrategy.onUpgrade`에 단계별 migration을 추가하고, v1 fixture에서 현재 schema로 열었을 때 사용자 데이터가 유지되는 테스트를 먼저 갱신합니다.

Migration 실패를 무시하고 DB를 삭제하거나 재생성하지 않습니다. 복구가 필요한 변경은 사용자 데이터 보존 범위, 실패 시 차단 동작, 롤백 가능 여부를 코드와 테스트로 먼저 고정한 뒤 릴리즈합니다.

production data pack의 pack URL과 sourceInventory URL은 공개 HTTPS host만 사용할 수 있으며, `localhost`, `*.localhost`, `*.local` 같은 local placeholder host를 쓰면 빌드와 검증 단계에서 실패해야 합니다. local placeholder host 값은 fixture artifact의 source 식별자 또는 manifest schema `$id`처럼 운영 배포 URL이 아닌 계약 값에만 남길 수 있습니다.

## Workspace

- `apps/mobile/`: Flutter Android/iOS app
- `backend/`: eGovFrame/Spring Boot backend modules
- `infra/`: local runtime and deployment infrastructure
- `scripts/`: data import and local development utilities
- `tools/ci/`: repository and CI contract checks

## Operations

운영 관측성과 알림 기준선은 `apps/mobile/release/operations-observability-gate.json`을 기준으로 검증합니다. 이 gate는 release blocker이며, PR에서는 `node --test tools/ci/*.test.mjs`로 필수 신호와 artifact 보관 계약을 확인합니다. 릴리즈 후보의 실제 CD, rollback, migration, restore rehearsal, alert routing 증거는 `apps/mobile/release/operations-release-evidence.json` 계약에 맞춰 `.codex/evidence/operations-release/<rc-or-run>/` 아래 로컬 전용으로 보관하고 PR에는 요약만 남깁니다.

백엔드 CD는 서버의 기존 PostgreSQL과 object-storage 컨테이너를 보존한 상태에서 backend 서비스만 교체합니다. 배포 스크립트는 배포 lock, main ancestry, 이전 배포 SHA, image drift, JAR checksum, env hash, migration 변경 시 PostgreSQL dump 검증, readiness, 실패 시 이전 backend image 재기동을 확인합니다. readiness 실패 로그와 백업 산출물은 서버의 `DEPLOY_ROOT` 아래에 보관하고 GitHub에는 민감값을 올리지 않습니다.

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

백업과 복구 리허설 기준선은 `apps/mobile/release/backup-restore-rehearsal-gate.json`으로 검증합니다. PR과 릴리즈 후보에서는 `node tools/ops/backup-restore-rehearsal-check.mjs`로 PostgreSQL dump, 신고 사진 object manifest, 데이터팩 source inventory, 데이터팩 release manifest history가 모두 복구 리허설 대상에 포함되는지 확인하고, 신고 사진 백업은 `node tools/ops/facility-report-photo-restore-check.mjs "$EASYSUBWAY_PHOTO_RESTORE_DIR"`로 `manifest.tsv`와 `objects/` 산출물을 검증합니다. 실제 database dump, 사진 object, signed URL, credential, receipt token은 GitHub에 올리지 않고 `.codex/evidence/backup-restore-rehearsal/<date>/` 아래 로컬 전용 증거로만 보관합니다.

backend static analysis feasibility gate는 `backend/quality/static-analysis-gate.json`으로 검증합니다. Checkstyle, SpotBugs, Error Prone, ArchUnit, JaCoCo는 P0 보안/경로/release contract가 안정화되고 CI runtime budget 측정이 끝나기 전까지 한 번에 필수 gate로 켜지 않습니다. 새 품질 도구를 추가할 때는 baseline 위반 수, suppression 근거, 추가 CI 시간, 기존 security/route/release 테스트 보존 여부를 먼저 PR 증거에 남깁니다.

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
