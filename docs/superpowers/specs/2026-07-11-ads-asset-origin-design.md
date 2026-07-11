# Production 광고 asset origin 배포 배선 설계

## 상태와 연결 이슈

- 상태: 구현 전 승인된 설계
- 작업 이슈: #1960
- 상위 이슈: #1771, #1762
- 위험도: A — production 배포와 사용자 노출 광고 동작에 영향을 준다.

## 문제

광고 관리 기능은 `AdService`의 `easysubway.ads.asset-origin`을 기준으로 이미지 URL이 승인된 first-party origin과 같은지 검사한다. 설정이 없거나 잘못되면 create, update, enable이 runtime에 fail-closed된다. 그러나 production의 단일 `EASYSUBWAY_ENV`에서 분리되는 `backend.env`에는 이 값을 전달하는 key가 없어 정상적인 광고 소재도 운영할 수 없다.

이 작업은 기존 배포 경로에 `EASYSUBWAY_ADS_ASSET_ORIGIN`을 backend 전용 필수값으로 연결하고, 잘못된 설정을 새 Compose 배포 전에 차단한다. 실제 production origin은 저장소, issue, PR, CI 로그, fixture에 기록하지 않는다.

## 목표

- `EASYSUBWAY_ADS_ASSET_ORIGIN`을 기존 `EASYSUBWAY_ENV`에서 `backend.env`로만 정확히 전달한다.
- production preflight에서 누락되거나 public HTTPS origin이 아닌 값을 fail-closed로 거부한다.
- Spring의 relaxed binding으로 기존 `easysubway.ads.asset-origin`에 값을 공급하고, `AdService`의 runtime same-origin 검증을 그대로 유지한다.
- 검증 실패 시 현재 운영 중인 배포를 건드리지 않고 새 배포를 시작하지 않는다.

## 비범위

- README와 상품 문구
- Java production source와 새 configuration abstraction
- `infra/docker-compose.yml`
- storage, bucket, IAM, CDN 생성 또는 변경
- 광고 소재 upload API/UI와 파일 전송
- 기존 report upload origin 재사용
- 별도 GitHub secret/variable overlay 또는 fallback provider
- 실제 production origin 결정·기록·DNS/HTTP reachability 검사

## 검토한 접근

### 1. 기존 단일 dotenv에 전용 backend key 추가 — 선택

`EASYSUBWAY_ADS_ASSET_ORIGIN`을 `.env.example`, env scope 계약, backend allowlist에 같은 이름으로 추가하고 기존 `prepare-deployment-env.sh`에서 검증한다. 현재의 secret 복원, allowlist 분리, 파일 권한, Compose `env_file`, Spring relaxed binding을 모두 재사용하므로 변경 범위와 새 실패 지점이 가장 작다.

### 2. report upload public base URL 재사용 — 제외

광고 소재 origin과 시설 제보 upload origin은 수명주기와 접근 정책이 다르다. 하나의 URL로 결합하면 어느 한쪽의 storage 이전이 다른 기능을 깨뜨리고 first-party 광고 경계가 불명확해진다.

### 3. 별도 secret 또는 Compose 환경변수 overlay 추가 — 제외

별도 GitHub secret이나 Compose `environment` 항목은 이미 존재하는 `EASYSUBWAY_ENV` → allowlist → `backend.env` 경로와 중복된다. 값의 출처와 검증 순서가 둘로 갈라지고 `infra/docker-compose.yml` 변경까지 유발하므로 채택하지 않는다.

## 구성과 데이터 흐름

```text
GitHub secret EASYSUBWAY_ENV
  → CD 임시 dotenv 파일
  → prepare-deployment-env.sh production preflight
  → backend-app-env.allowlist
  → backend.env (0600)
  → 기존 Compose backend env_file
  → Spring relaxed binding
  → easysubway.ads.asset-origin
  → 기존 AdService same-origin 검사
```

`contracts/env/env-scope-map.json`은 새 key를 `backend` scope 하나에만 배정한다. `.env.example`에는 key를 빈 값으로만 추가해 key 집합 계약을 맞추며 실제 origin을 제시하지 않는다. `tools/deploy/backend-app-env.allowlist`에는 새 key를 추가하지만 `compose-server-env.allowlist`에는 추가하지 않는다. 따라서 유효한 source line은 기존 출력 로직에 의해 변형 없이 `backend.env`에 기록되고 `compose.env`에는 나타나지 않는다.

`infra/docker-compose.yml`은 이미 backend 서비스의 `env_file`로 준비된 `backend.env`를 읽는다. Spring은 `EASYSUBWAY_ADS_ASSET_ORIGIN`을 `easysubway.ads.asset-origin`으로 매핑하므로 Compose나 Java를 수정하지 않는다.

## Production preflight 계약

`prepare-deployment-env.sh`의 기존 dotenv parser가 형식, 중복 key, cross-key interpolation을 먼저 검사한다. 새 검증은 parser가 따옴표를 제거해 제공하는 값만 판정하고 오류 메시지에는 key 이름과 실패 종류만 출력한다. 값 자체는 출력하지 않는다.

다음 조건을 모두 만족해야 한다.

1. `EASYSUBWAY_ADS_ASSET_ORIGIN`이 정확히 한 번 존재하고 값이 비어 있지 않다.
2. absolute `https://` origin이며 host가 있다. port를 쓰면 1~65535만 허용하고 끝의 단일 `/`는 허용한다.
3. userinfo, root가 아닌 path, query, fragment, 공백은 없다.
4. host는 ASCII 영문자·숫자·하이픈으로 이루어진 label이 점으로 둘 이상 연결된 DNS hostname이어야 한다. label의 처음과 끝에 하이픈을 허용하지 않는다.
5. IPv4·IPv6 literal 전체, `localhost` 또는 그 하위 domain, `.local`·`.internal` suffix, Compose 내부 single-label service host를 거부한다. IP literal을 전부 거부하므로 loopback·사설·link-local 주소도 함께 차단된다.
6. host label이 `placeholder`, `change-me`, `changeme`, `todo`, `tbd`인 명백한 미완성 값은 거부한다.

여기서 public 판정은 배포 입력의 정적 형식과 알려진 내부 주소 차단을 뜻한다. preflight는 DNS 조회나 HTTP 요청을 하지 않는다. 외부 네트워크 상태를 배포 결정에 섞거나 검증 과정에서 승인 전 origin을 노출하지 않기 위해서다. 테스트 fixture는 실제 production 값이 아닌, 기존 저장소 관례에 맞는 명백한 test-only HTTPS origin을 사용하며 위 금지 label은 사용하지 않는다.

검증 실패는 `prepare-deployment-env.sh`를 non-zero로 종료한다. CD의 Compose config와 local deploy 단계보다 앞에서 종료되므로 새 container 생성, 기존 container 중지, env set 교체가 일어나지 않는다. 별도 fallback이나 이전 origin 자동 재사용은 하지 않는다.

## Runtime 경계

preflight는 배포 구성의 조기 검증이고, 보안 경계의 최종 집행자는 기존 `AdService`다. `AdService`는 설정 origin 자체가 HTTPS origin인지 다시 확인하고, 광고 이미지 URL의 scheme, host, effective port가 설정값과 같은지 검사한다. 이 이중 검사는 의도된 방어 계층이므로 Java 검증을 제거하거나 shell과 공유하는 새 abstraction으로 옮기지 않는다.

landing URL은 기존 정책대로 absolute HTTPS만 요구하며 asset origin과 같을 필요가 없다. 이 작업은 광고 소재의 생성·저장·upload 기능을 추가하지 않는다.

## TDD와 검증

구현은 다음 순서로 진행한다.

1. `tools/ci/backend-deploy.test.mjs`에 valid test origin이 `backend.env`에 전달되고 `compose.env`에는 없는 계약을 추가해 RED를 확인한다.
2. 같은 테스트에 missing, blank, HTTP, userinfo, non-root path, query, fragment, localhost/loopback/private/internal host, placeholder의 negative matrix를 추가해 현재 통과하는 잘못된 입력이 RED임을 확인한다.
3. `.env.example`, `contracts/env/env-scope-map.json`, `tools/deploy/backend-app-env.allowlist`, test fixture를 최소 변경한다.
4. `prepare-deployment-env.sh`에 필수 public HTTPS origin 검증을 추가하고 focused test를 GREEN으로 만든다.
5. 값이 오류 출력에 포함되지 않고 source의 유효 line이 `backend.env`에만 그대로 남는지 확인한다.

완료 전 다음 검증을 실행한다.

```bash
node --test tools/ci/backend-deploy.test.mjs tools/ci/check-contracts.test.mjs
node tools/ci/check-contracts.mjs
node --test tools/ci/repository-contract.test.mjs
backend/gradlew -p backend test --tests com.easysubway.ads.application.service.AdServiceTest --no-daemon
bash -n tools/deploy/prepare-deployment-env.sh
git diff --check
```

검증 증거에는 RED/GREEN 명령과 결과, key가 `backend.env`에만 존재한다는 redacted 확인, invalid matrix 결과를 남긴다. 실제 origin이나 credential은 출력하지 않는다. 변경 파일 감사에서 README, Java production source, Compose, storage, upload 경로가 diff에 없음을 확인한다.

## 배포와 운영 순서

1. 외부 owner가 승인한 실제 first-party origin을 production 환경에 준비한다.
2. owner가 실제 값을 기존 `EASYSUBWAY_ENV` secret에 out-of-band로 추가한다. 저장소와 GitHub 본문에는 값 대신 redacted presence evidence만 남긴다.
3. #1960의 Risk A PR에서 required CI, canonical GitHub PR Review, requested changes 부재, unresolved thread 0건을 확인한다.
4. 병합 뒤 main CI와 관련 CD를 확인한다. preflight 실패 시 값을 로그에 출력하지 않고 배포를 중단하며 기존 배포를 유지한다.
5. 성공 시 준비된 `backend.env`를 사용하는 기존 배포 절차를 계속하고, post-merge CI/CD 링크와 최종 상태를 기록한다.

PR은 `Closes #1960`, `Refs #1771`, `Refs #1762`로 연결한다. 이 작업은 배포 배선만 완료하며 storage와 upload가 별도 승인·완료되지 않았다면 그것을 광고 소재 공급 완료로 해석하지 않는다.
