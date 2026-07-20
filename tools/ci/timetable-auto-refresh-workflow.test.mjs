import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const workflowPath = ".github/workflows/timetable-auto-refresh.yml";
const workflow = readFileSync(workflowPath, "utf8");
const alerts = readFileSync("infra/prometheus/alerts.yml", "utf8");

test("만료 이전 스케줄과 dry-run/force 수동 트리거를 노출한다", () => {
  assert.match(workflow, /^ {2}schedule:$/m);
  assert.match(workflow, /- cron: "0 20 \* \* \*"/);
  const inputsBlock = workflow.slice(workflow.indexOf("    inputs:"), workflow.indexOf("\nconcurrency:"));
  assert.match(inputsBlock, /force_refresh:/);
  assert.match(inputsBlock, /dry_run:/);
});

test("트리거는 schedule과 workflow_dispatch만 허용한다 — pull_request 유입 시 fork에서 DATA_GO_KR_SERVICE_KEY 노출 위험", () => {
  const lines = workflow.split("\n");
  const onIndex = lines.findIndex((line) => line === "on:");
  assert.notEqual(onIndex, -1);
  const triggers = [];
  for (let index = onIndex + 1; index < lines.length; index += 1) {
    const line = lines[index];
    if (/^\S/.test(line)) break; // 다음 최상위(0-indent) 섹션(concurrency: 등) 진입 시 종료
    const match = line.match(/^ {2}([a-z_]+):/);
    if (match) triggers.push(match[1]);
  }
  assert.deepEqual(triggers, ["schedule", "workflow_dispatch"]);
  assert.doesNotMatch(workflow, /^ {2}pull_request:/m);
  assert.doesNotMatch(workflow, /^ {2}pull_request_target:/m);
});

test("워크플로 권한은 read 전용이며 write 권한을 요구하지 않는다", () => {
  assert.match(workflow, /^permissions:\n {2}contents: read$/m);
  assert.doesNotMatch(workflow, /contents:\s*write/);
  assert.doesNotMatch(workflow, /pull-requests:\s*write/);
  assert.doesNotMatch(workflow, /\bautomerge\b/i);
});

test("pinned action SHA와 Node 24를 사용한다", () => {
  assert.match(workflow, /actions\/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd/);
  assert.match(workflow, /actions\/setup-node@48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e/);
  assert.match(workflow, /node-version: "24"/);
  assert.match(workflow, /actions\/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02/);
  assert.match(workflow, /slackapi\/slack-github-action@45a88b9581bfab2566dc881e2cd66d334e621e2c/);
});

test("잔여 유효기간을 계산해 github-output과 metrics를 남기고 critical에서 실패한다", () => {
  assert.match(workflow, /node tools\/datapack\/check-timetable-snapshot-freshness\.mjs/);
  assert.match(workflow, /--github-output "\$\{GITHUB_OUTPUT\}"/);
  assert.match(workflow, /--metrics-output "\$\{EASYSUBWAY_TIMETABLE_FRESHNESS_METRICS\}"/);
  assert.match(workflow, /if:\s*\$\{\{ steps\.check\.outputs\.severity == 'critical' \}\}[\s\S]*?exit 1/);
});

test("Slack webhook 미설정 시 알림을 건너뛰고 fail 하지 않는다", () => {
  assert.match(workflow, /env\.SLACK_RELEASE_WEBHOOK_URL == ''[\s\S]*?::notice/);
  assert.match(workflow, /env\.SLACK_RELEASE_WEBHOOK_URL != ''/);
});

test("check 스텝 자체가 죽어도(watchdog 고장) Slack으로 보고한다", () => {
  assert.match(
    workflow,
    /Notify Slack on watchdog failure[\s\S]*?if:\s*\$\{\{ failure\(\) && steps\.check\.outcome == 'failure' && env\.SLACK_RELEASE_WEBHOOK_URL != '' \}\}/,
  );
  assert.match(
    workflow,
    /Skip missing Slack webhook for watchdog failure[\s\S]*?if:\s*\$\{\{ failure\(\) && steps\.check\.outcome == 'failure' && env\.SLACK_RELEASE_WEBHOOK_URL == '' \}\}/,
  );
});

test("auto-refresh는 refresh lead 창 또는 force 시에만 실행되고 alert job에 의존한다", () => {
  assert.match(workflow, /auto-refresh:/);
  assert.match(workflow, /needs: snapshot-freshness-alert/);
  assert.match(
    workflow,
    /if:\s*\$\{\{ always\(\) && \(needs\.snapshot-freshness-alert\.outputs\.should_refresh == 'true' \|\| \(github\.event_name == 'workflow_dispatch' && inputs\.force_refresh\)\) \}\}/,
  );
});

test("DATA_GO_KR_SERVICE_KEY 미설정·멀티라인은 fail closed 하고 dry-run은 네트워크를 건너뛴다", () => {
  assert.match(workflow, /DATA_GO_KR_SERVICE_KEY: \$\{\{ secrets\.DATA_GO_KR_SERVICE_KEY \}\}/);
  assert.match(workflow, /if \[\[ -z "\$\{DATA_GO_KR_SERVICE_KEY\}" \]\]; then[\s\S]*?exit 1/);
  assert.match(workflow, /must be a single line[\s\S]*?exit 1/);
  assert.match(workflow, /github\.event_name == 'workflow_dispatch' && inputs\.dry_run/);
});

test("collect는 admission service dates를 전달하고 승격은 UNCHANGED_AUTO 조건에서만 실행한다", () => {
  assert.match(workflow, /node tools\/datapack\/collect-korail-itx-cheongchun-timetable\.mjs/);
  assert.match(workflow, /--day8-date "\$\{DAY8_DATE\}"/);
  assert.match(workflow, /--day7-date "\$\{DAY7_DATE\}"/);
  assert.match(workflow, /--day9-date "\$\{DAY9_DATE\}"/);
  assert.match(
    workflow,
    /steps\.collect\.outputs\.collect_exit == '0' && steps\.collect\.outputs\.promotion_status == 'SUPPORTED'/,
  );
  assert.match(workflow, /--promote-candidate "\$\{EASYSUBWAY_ITX_CANDIDATE\}"/);
});

test("승인 게이트를 우회하지 않고 review-required·수집 실패 시 fail closed 한다", () => {
  assert.match(
    workflow,
    /if:\s*\$\{\{ !\(github\.event_name == 'workflow_dispatch' && inputs\.dry_run\) && !\(steps\.collect\.outputs\.collect_exit == '0' && steps\.collect\.outputs\.promotion_status == 'SUPPORTED'\) \}\}/,
  );
  assert.match(workflow, /fail closed[\s\S]*?exit 1/);
  // 승인 인자를 CLI 플래그로 자동 주입해 게이트를 우회하지 않는다.
  assert.doesNotMatch(workflow, /--approved-sha256\s+["$]/);
  assert.doesNotMatch(workflow, /--approval-url\s+["$]/);
});

test("UNCHANGED_AUTO 안내는 원커맨드 적용 도구 사용법을 현행화한다", () => {
  assert.match(
    workflow,
    /node tools\/datapack\/apply-timetable-refresh\.mjs --patch/,
  );
  assert.match(workflow, /promotion\.patch/);
});

test("Prometheus alerts는 T-24h/T-6h 임계값을 구성한다", () => {
  assert.match(alerts, /alert: TimetableSnapshotFreshnessExpiringT24h/);
  assert.match(alerts, /alert: TimetableSnapshotFreshnessExpiringT6h/);
  assert.match(alerts, /easysubway_timetable_snapshot_remaining_seconds\) <= 86400/);
  assert.match(alerts, /easysubway_timetable_snapshot_remaining_seconds\) <= 21600/);
  assert.match(alerts, /severity: warning/);
  assert.match(alerts, /severity: critical/);
});
