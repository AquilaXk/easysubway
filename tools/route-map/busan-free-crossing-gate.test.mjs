// #2068 부산 마감 라운드: 파이프라인 실측 자유 교차(비환승 노선-노선 교차) 하드
// 게이트. capital.sqlite.gz의 실제 부산권 팩(run-sma-pipeline-busan.sh 산출물)에
// audit-station-spacing.mjs와 동일한 classifyCrossings를 돌려 자유 교차 수를
// 감시한다 — 회귀(재배치·재간격·스냅 조정이 새 자유 교차를 만드는 것)를 막는다.
//
// 재설계(#2068) 전 자유 교차 6(오너 지적 "환승 아닌데 노선 겹침") → line1·line2·
// bgl corridor 분리 + 벡스코 진입부 8선형 코너 재설계로 소스 SVG 자유 교차는 0.
// 파이프라인(재간격→8선형 스냅) 통과 후 1건 잔존했었다 — 원인 실측: 벡스코(시립
// 미술관)는 SVG에 환승 캡슐(2호선×동해선)이 그려지지만, 카탈로그에는 두 노선이
// 별개 station_id로 남아 있어 graph.clusters에 벡스코가 knot로 등록되지 않았다.
// classifyCrossings는 knot 반경 안의 교차만 "매듭"으로 걸러내므로, 두 노선이
// 벡스코에서 만나는 한 이 교차는 "자유"로 분류됐다 — 스냅 파라미터가 아니라
// 카탈로그의 station_id 병합 여부에 달린 데이터 모델 문제였다.
//
// #2068 마감(오너 확정 "실제로 환승역임, 이 이슈에서 처리"): merge-busan-transfers.mjs
// 로 2호선 벡스코(station-fbcc387e1db9, 부역명 시립미술관)와 동해선 벡스코
// (station-6820d21cea02)를 단일 환승 station_id로 병합했다. 이제 벡스코가 2노선
// 멤버 = graph.clusters의 knot로 등록돼(cluster members 2) 그 교차가 매듭으로
// 분류된다 → 자유 교차 1→0. 좌천 분리(split-mismerged-stations)와 대칭인 카탈로그
// 수술이며, 병합 후 apply-sma-svg-positions 미매핑 0 게이트도 통과함을 실측했다.
// 하드 게이트는 자유 교차 0을 못 박고, 재배치·재간격·스냅 회귀가 새 자유 교차를
// 만들면 즉시 실패시킨다.
import assert from "node:assert/strict";
import { test } from "node:test";
import { classifyCrossings, clusterCentroids } from "./audit-station-spacing.mjs";
import { loadRegionRespaceGraph, medianStationChainLength } from "./respace-route-map.mjs";
import { cleanupPackDir, openPack } from "./pack-io.mjs";

const KNOWN_FREE_CROSSING_BASELINE = 0; // 벡스코 병합 완료 — 자유 교차 0(위 note 참고).

test("부산권 실팩: 자유 교차 0(벡스코 병합 완료, #2068 마감)", () => {
  const { db, dir } = openPack("apps/mobile/assets/datapacks/capital.sqlite.gz", "busan-free-crossing-gate-");
  try {
    const graph = loadRegionRespaceGraph(db, "부산권");
    const tracksPoints = graph.tracks
      .filter((t) => t.nodeIds.length)
      .map((t) => t.nodeIds.map((id) => graph.nodes[id]));
    const unit = medianStationChainLength(graph);
    const byClass = classifyCrossings(tracksPoints, clusterCentroids(graph, graph.nodes), {
      knotRadius: unit * 0.75,
    });
    assert.ok(
      byClass.free <= KNOWN_FREE_CROSSING_BASELINE,
      `부산권 자유 교차 ${byClass.free}건 — baseline ${KNOWN_FREE_CROSSING_BASELINE}(벡스코 병합 완료) 악화 금지. ` +
        `새 자유 교차가 생겼으면 재배치로 제거를 먼저 시도하라(#2068 오너 지적: 비환승 교차 최소화).`,
    );
  } finally {
    try {
      db.close();
    } catch {
      /* 이미 닫힘 */
    }
    cleanupPackDir(dir);
  }
});
