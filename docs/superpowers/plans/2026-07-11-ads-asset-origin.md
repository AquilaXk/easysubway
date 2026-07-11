# Production Ads Asset Origin Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route the required `EASYSUBWAY_ADS_ASSET_ORIGIN` through the existing production backend env path and reject unsafe values before a new Compose deployment starts.

**Architecture:** Extend the existing `EASYSUBWAY_ENV` → allowlist → `backend.env` pipeline with one backend-scoped key. Keep the existing Spring relaxed binding and `AdService` runtime same-origin check unchanged; add the smallest static public-HTTPS validation block to `prepare-deployment-env.sh` so failures occur before Compose deployment.

**Tech Stack:** Bash deployment tooling, Node.js built-in `node:test`, JSON env-scope contract, Docker Compose `env_file`, existing Spring Boot relaxed binding.

## Global Constraints

- Risk A tracked work: `Closes #1960`, `Refs #1771`, `Refs #1762`; preserve the review → required CI → auto-merge → issue-close gate order.
- The only new production key is `EASYSUBWAY_ADS_ASSET_ORIGIN`; it comes from the existing `EASYSUBWAY_ENV` and is written only to `backend.env`.
- Never record the actual production origin in source, fixture, issue/PR text, CI logs, or evidence. The tracked fixture value must remain visibly test-only.
- Accept only an absolute `https://` DNS origin with at least two valid ASCII labels, optional canonical decimal port `1`–`65535`, and optional trailing `/`.
- Reject missing/blank values, userinfo, non-root path, query, fragment, whitespace, IPv4/IPv6 literals, localhost/internal hosts, and explicit unfinished host labels.
- Error output contains the key and failure class, never the supplied origin value. There is no fallback, DNS lookup, or HTTP probe.
- Reuse `AdService` and Spring relaxed binding. Do not change README, Java production source, `infra/docker-compose.yml`, storage/bucket/IAM/CDN, or asset upload API/UI.
- Add no dependency, helper file, configuration abstraction, or setup/scaffold task.

---

### Task 1: Route the dedicated key into `backend.env`

**Files:**
- Modify: `.env.example:8-11`
- Modify: `contracts/env/env-scope-map.json:12-16`
- Modify: `tools/deploy/backend-app-env.allowlist:1-7`
- Modify: `tools/ci/fixtures/deployment-prod-valid.env:8-12`
- Test: `tools/ci/backend-deploy.test.mjs:10-75`

**Interfaces:**
- Consumes: existing `fixtureEnv(): string` and `prepare(source: string): Promise<string>` test helpers.
- Produces: dotenv key `EASYSUBWAY_ADS_ASSET_ORIGIN`, scoped exactly as `backend`; test constants `ASSET_ORIGIN: string` and `ASSET_ORIGIN_LINE: string` for Task 2.
- Runtime mapping: `EASYSUBWAY_ADS_ASSET_ORIGIN` → existing Spring property `easysubway.ads.asset-origin`; no Java or Compose interface changes.

- [ ] **Step 1: Add the test-only input and write the focused routing test**

In `tools/ci/fixtures/deployment-prod-valid.env`, add the test-only line immediately after `EASYSUBWAY_REPORT_API_BASE_URL`:

```dotenv
EASYSUBWAY_ADS_ASSET_ORIGIN=https://ads-assets.fixture.easysubway.example
```

In `tools/ci/backend-deploy.test.mjs`, add these constants after `execFileAsync` and add the new test after `prepare`:

```js
const ASSET_ORIGIN = "https://ads-assets.fixture.easysubway.example";
const ASSET_ORIGIN_LINE = `EASYSUBWAY_ADS_ASSET_ORIGIN=${ASSET_ORIGIN}`;

test("광고 asset origin은 backend env에만 변형 없이 전달한다", async () => {
  const outputDir = await prepare(fixtureEnv());
  const composeEnv = await readFile(path.join(outputDir, "compose.env"), "utf8");
  const backendEnv = await readFile(path.join(outputDir, "backend.env"), "utf8");

  assert.ok(
    backendEnv.split("\n").includes(ASSET_ORIGIN_LINE),
    "backend.env must contain the exact asset origin line",
  );
  assert.ok(
    !composeEnv.split("\n").includes(ASSET_ORIGIN_LINE),
    "compose.env must not contain the asset origin line",
  );
});
```

- [ ] **Step 2: Run the focused test and capture RED**

Run:

```bash
node --test --test-name-pattern='광고 asset origin은 backend env에만 변형 없이 전달한다' tools/ci/backend-deploy.test.mjs
```

Expected: FAIL with `backend.env must contain the exact asset origin line`; the current backend allowlist drops the new source line.

- [ ] **Step 3: Add the minimal env key contract and backend allowlist entry**

Add the empty key to `.env.example` after `EASYSUBWAY_REPORT_API_BASE_URL`:

```dotenv
EASYSUBWAY_ADS_ASSET_ORIGIN=
```

Add the backend-only mapping to `contracts/env/env-scope-map.json` after `EASYSUBWAY_REPORT_API_BASE_URL`:

```json
"EASYSUBWAY_ADS_ASSET_ORIGIN": ["backend"],
```

Add the key to `tools/deploy/backend-app-env.allowlist` after `EASYSUBWAY_REPORT_API_BASE_URL`:

```text
EASYSUBWAY_ADS_ASSET_ORIGIN
```

Do not add it to `tools/deploy/compose-server-env.allowlist`.

- [ ] **Step 4: Run focused routing and env-contract tests and capture GREEN**

Run:

```bash
node --test --test-name-pattern='광고 asset origin은 backend env에만 변형 없이 전달한다' tools/ci/backend-deploy.test.mjs
node --test tools/ci/check-contracts.test.mjs
node tools/ci/check-contracts.mjs
```

Expected: the focused test passes, `check-contracts.test.mjs` passes all tests, and `check-contracts.mjs` exits 0 with no contract error.

- [ ] **Step 5: Commit the routed env contract**

```bash
git add .env.example contracts/env/env-scope-map.json tools/deploy/backend-app-env.allowlist tools/ci/fixtures/deployment-prod-valid.env tools/ci/backend-deploy.test.mjs
git commit -m "feat(deploy): 광고 asset origin backend env 배선 (#1960)"
```

Expected: one commit containing only the five listed files.

### Task 2: Fail closed on unsafe production origins

**Files:**
- Modify: `tools/ci/backend-deploy.test.mjs:13-135`
- Test: `tools/ci/repository-contract.test.mjs:1245-1300`
- Modify: `tools/deploy/prepare-deployment-env.sh:92-180`

**Interfaces:**
- Consumes: Task 1 constants `ASSET_ORIGIN: string`, `ASSET_ORIGIN_LINE: string`, existing `fixtureEnv(): string`, existing `prepare(source: string): Promise<string>`, and shell `value <NAME>`.
- Produces: test helper `withAssetOrigin(origin: string): string`; no new production function or file. The inline preflight block exits `1` on invalid input and falls through without changing the source line on valid input.
- Error contract: missing/empty emits `required deployment env is empty: EASYSUBWAY_ADS_ASSET_ORIGIN`; other unsafe values emit `invalid public HTTPS origin: EASYSUBWAY_ADS_ASSET_ORIGIN`.

- [ ] **Step 1: Add the negative matrix and allowed-boundary test**

Add this helper after `fixtureEnv` in `tools/ci/backend-deploy.test.mjs`:

```js
function withAssetOrigin(origin) {
  return fixtureEnv().replace(
    ASSET_ORIGIN_LINE,
    `EASYSUBWAY_ADS_ASSET_ORIGIN=${origin}`,
  );
}

async function assertInvalidAssetOrigin(origin) {
  await assert.rejects(
    prepare(withAssetOrigin(origin)),
    (error) => {
      const stderr = String(error.stderr ?? "");
      assert.match(
        stderr,
        /invalid public HTTPS origin: EASYSUBWAY_ADS_ASSET_ORIGIN/,
      );
      if (origin.trim()) {
        assert.equal(stderr.includes(origin), false, "stderr must not contain the origin value");
      }
      return true;
    },
  );
}
```

Add this test after the Task 1 routing test:

```js
test("광고 asset origin production preflight는 unsafe 값을 차단한다", async () => {
  await assert.rejects(
    prepare(fixtureEnv().replace(`${ASSET_ORIGIN_LINE}\n`, "")),
    /required deployment env is empty: EASYSUBWAY_ADS_ASSET_ORIGIN/,
  );
  await assert.rejects(
    prepare(withAssetOrigin("")),
    /required deployment env is empty: EASYSUBWAY_ADS_ASSET_ORIGIN/,
  );
  await assert.rejects(
    prepare(`${fixtureEnv()}${ASSET_ORIGIN_LINE}\n`),
    /duplicate dotenv key: EASYSUBWAY_ADS_ASSET_ORIGIN/,
  );

  for (const origin of [
    " ",
    "http://ads-assets.fixture.easysubway.example",
    "https://user@ads-assets.fixture.easysubway.example",
    "https://ads-assets.fixture.easysubway.example/ads",
    "https://ads-assets.fixture.easysubway.example?revision=1",
    "https://ads-assets.fixture.easysubway.example#creative",
    "https://localhost",
    "https://127.0.0.1",
    "https://[::1]",
    "https://10.0.0.1",
    "https://object-storage",
    "https://assets.internal",
    "https://placeholder.example.com",
    "https://todo.example.com",
    "https://-assets.example.com",
    "https://assets.example.com:0",
    "https://assets.example.com:65536",
  ]) {
    await assertInvalidAssetOrigin(origin);
  }

  for (const origin of [
    `${ASSET_ORIGIN}/`,
    "https://ads-assets.fixture.easysubway.example:8443",
  ]) {
    const outputDir = await prepare(withAssetOrigin(origin));
    const backendEnv = await readFile(path.join(outputDir, "backend.env"), "utf8");
    assert.ok(
      backendEnv.split("\n").includes(`EASYSUBWAY_ADS_ASSET_ORIGIN=${origin}`),
      "backend.env must preserve an allowed origin exactly",
    );
  }
});
```

- [ ] **Step 2: Run the preflight test and capture RED**

Run:

```bash
node --test --test-name-pattern='광고 asset origin production preflight는 unsafe 값을 차단한다' tools/ci/backend-deploy.test.mjs
```

Expected: FAIL with `Missing expected rejection` at the missing-key assertion because the current preflight does not require or validate the key.

- [ ] **Step 3: Add the minimum inline public-HTTPS validation block**

In `tools/deploy/prepare-deployment-env.sh`, add the required key beside the existing `require_nonempty` calls, then place the inline validation block before `receipt_pepper` is read:

```bash
require_nonempty EASYSUBWAY_ADS_ASSET_ORIGIN

ads_asset_origin="$(value EASYSUBWAY_ADS_ASSET_ORIGIN)"
ads_asset_authority="${ads_asset_origin#https://}"
ads_asset_authority="${ads_asset_authority%/}"
ads_asset_host="${ads_asset_authority%%:*}"
ads_asset_port=""
if [[ "${ads_asset_authority}" == *:* ]]; then
	ads_asset_port="${ads_asset_authority##*:}"
fi
ads_asset_host_normalized="$(printf '%s' "${ads_asset_host}" | tr '[:upper:]' '[:lower:]')"
ads_asset_origin_invalid=0

if [[ ! "${ads_asset_origin}" =~ ^https://([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(:[1-9][0-9]{0,4})?/?$ ]]; then
	ads_asset_origin_invalid=1
fi
if [[ "${ads_asset_host}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
	ads_asset_origin_invalid=1
fi
if [[ "${ads_asset_port}" =~ ^[0-9]+$ && "${ads_asset_port}" -gt 65535 ]]; then
	ads_asset_origin_invalid=1
fi
case ".${ads_asset_host_normalized}." in
	*.localhost.*|*.local.|*.internal.|*.placeholder.*|*.change-me.*|*.changeme.*|*.todo.*|*.tbd.*)
		ads_asset_origin_invalid=1
		;;
esac
if [[ "${ads_asset_origin_invalid}" -ne 0 ]]; then
	printf 'invalid public HTTPS origin: %s\n' EASYSUBWAY_ADS_ASSET_ORIGIN >&2
	exit 1
fi
```

This is intentionally inline: there is one caller, so a helper module or shared URL abstraction would add surface without reducing duplication. The original dotenv line remains in `env_lines_file`; successful output therefore preserves it byte-for-byte.

- [ ] **Step 4: Run the focused routing and preflight tests and capture GREEN**

Run:

```bash
node --test --test-name-pattern='광고 asset origin' tools/ci/backend-deploy.test.mjs
```

Expected: both ad asset-origin tests pass; invalid cases reject without echoing their supplied values, and allowed `/`/port cases are preserved exactly.

- [ ] **Step 5: Run the complete local contract verification**

The repository contract uses a hardcoded deployment env fixture. Since Task 1 makes the new key required, add the same visibly test-only origin to `deploymentEnvLines` after `EASYSUBWAY_REPORT_API_BASE_URL`:

```js
"EASYSUBWAY_ADS_ASSET_ORIGIN=https://ads-assets.fixture.easysubway.example",
```

This fixture-only update keeps the integration contract aligned without introducing an actual production origin.

Run each command and retain its exit status:

```bash
node --test tools/ci/backend-deploy.test.mjs tools/ci/check-contracts.test.mjs
node tools/ci/check-contracts.mjs
node --test tools/ci/repository-contract.test.mjs
```

Expected: all Node tests pass and the contract CLI exits 0 without errors.

- [ ] **Step 6: Verify the unchanged runtime boundary and shell syntax**

Run:

```bash
backend/gradlew -p backend test --tests com.easysubway.ads.application.service.AdServiceTest --no-daemon
bash -n tools/deploy/prepare-deployment-env.sh
git diff --check
```

Expected: `AdServiceTest` passes, Bash syntax exits 0, and `git diff --check` prints nothing.

- [ ] **Step 7: Audit the file boundary and secret hygiene**

Run:

```bash
git diff --name-only fb9d3e29
git diff fb9d3e29 -- . ':!docs/superpowers/specs/**' ':!docs/superpowers/plans/**' | rg -n 'https://[^[:space:]`"]+' || true
```

Expected: implementation changes are limited to `.env.example`, `contracts/env/env-scope-map.json`, `tools/ci/backend-deploy.test.mjs`, `tools/ci/fixtures/deployment-prod-valid.env`, `tools/ci/repository-contract.test.mjs`, `tools/deploy/backend-app-env.allowlist`, and `tools/deploy/prepare-deployment-env.sh`. URL matches are existing or visibly test-only; there is no actual production origin. README, Java, Compose, storage, and upload paths are absent.

- [ ] **Step 8: Commit the fail-closed preflight**

```bash
git add tools/ci/backend-deploy.test.mjs tools/ci/repository-contract.test.mjs tools/deploy/prepare-deployment-env.sh
git commit -m "feat(deploy): 광고 asset origin preflight 강화 (#1960)"
```

Expected: a second implementation commit containing only the focused test, repository contract fixture, and deployment script.

## Risk A Review and Deployment Handoff

- [ ] Confirm the owner has added the approved origin to the existing production `EASYSUBWAY_ENV` out-of-band; record only redacted key-presence evidence.
- [ ] Open the full-template PR with `Closes #1960`, `Refs #1771`, and `Refs #1762`; do not paste the origin into the body or logs.
- [ ] Complete canonical GitHub PR Review first, resolve every actionable finding/requested change, and verify unresolved review threads are `0`.
- [ ] Confirm every required CI check passes, then enable auto-merge; after merge, confirm #1960 closes.
- [ ] Check post-merge main CI and related CD. If preflight fails, verify no new Compose deployment started and the prior deployment remained active; retain only redacted evidence and workflow links.
