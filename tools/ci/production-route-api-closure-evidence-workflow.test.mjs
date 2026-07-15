import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const workflowPath = ".github/workflows/production-route-api-closure-evidence.yml";

test("production route API closure evidence는 현재 배포와 origin 403·row 불변을 검증한다", async () => {
  const workflow = await readFile(workflowPath, "utf8");

  assert.match(workflow, /^on:\n  push:\n    branches:\n      - main\n    paths:/m);
  assert.doesNotMatch(workflow, /workflow_dispatch/);
  assert.match(workflow, /EXPECTED_SHA: cba25764de4ed646e398b2141b64fa41767ed3cc/);
  assert.match(workflow, /EXPECTED_IMAGE_DIGEST: sha256:ef9067f8890e72a5a4cd2fa3ab478d80951e577042e3016bff266b2fd24859e8/);
  assert.match(workflow, /runs-on:\n\s+- self-hosted\n\s+- easysubway-production/);
  assert.doesNotMatch(workflow, /environment:\n\s+name: production/);
  assert.match(workflow, /permissions:\n\s+contents: read/);
  assert.match(workflow, /group: cd-production-deploy/);

  assert.match(workflow, /shared\/current-sha/);
  assert.match(workflow, /shared\/current-image-digest/);
  assert.match(workflow, /\.Config\.Image/);
  assert.match(workflow, /\.RepoDigests/);
  assert.match(workflow, /--format '\{\{\.Image\}\}'/);
  assert.match(workflow, /easysubway-backend/);
  assert.match(workflow, /easysubway-back-worker/);
  assert.match(workflow, /\/api\/v1\/routes\/search/);
  assert.match(workflow, /\/api\/v2\/routes\/search/);
  assert.match(workflow, /\/api\/v2\/routes\/closure-probe\/refresh/);
  assert.match(workflow, /--noproxy '\*'/);
  assert.match(workflow, /status[^\n]+!= "403"/);
  assert.doesNotMatch(workflow, /retry|acceptedStatuses|404/);

  assert.match(workflow, /SELECT count\(\*\) FROM route_search_results/);
  assert.match(workflow, /row_count_before/);
  assert.match(workflow, /row_count_after/);
  assert.match(workflow, /row_count_before[^\n]+!=[^\n]+row_count_after/);
});
