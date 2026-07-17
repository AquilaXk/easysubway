// #2068 부산 마감 라운드: 파이프라인 실측 자유 교차(비환승 노선-노선 교차) 하드
// 게이트. capital.sqlite.gz의 실제 부산권 팩(run-sma-pipeline-busan.sh 산출물)에
// audit-station-spacing.mjs와 동일한 classifyCrossings를 돌려 자유 교차 수를
// 감시한다 — 회귀(재배치·재간격·스냅 조정이 새 자유 교차를 만드는 것)를 막는다.
//
// 재설계(#2068) 전 자유 교차 6(오너 지적 "환승 아닌데 노선 겹침") → line1·line2·
// bgl corridor 분리 + 벡스코 진입부 8선형 코너 재설계로 소스 SVG 자유 교차는 0.
// 파이프라인(재간격→8선형 스냅) 통과 후 1건 잔존 — 원인 실측: 벡스코(시립미술관)
// 는 SVG에 환승 캡슐(2호선×동해선)이 그려지지만, 카탈로그에는 두 노선이 별개
// station_id로 남아 있어(부전·좌천과 동일 패턴 — route_map_label_layout.dart의
// "#2068 부산 5차: 동명 폴백 억제" 주석 참고) graph.clusters에 벡스코가 knot로
// 등록되지 않는다. classifyCrossings는 knot 반경 안의 교차만 "매듭"으로 걸러내므로,
// 지오메트리를 아무리 조정해도(2026-07-18 실측: 여러 재배치 시도 전부 실패)
// 두 노선이 벡스코에서 만나는 한 이 교차는 "자유"로 분류된다 — 스냅 파라미터가
// 아니라 카탈로그의 station_id 병합 여부에 달린 데이터 모델 한계다. 카탈로그 병합은
// 부전·좌천과 동일한 광역 영향(히트 타깃·접근성) 재검토가 필요해 이 라운드 범위
// 밖이다. 하드 게이트는 이 알려진 1건만 허용하고 그 이상은 즉시 실패시킨다.
import assert from "node:assert/strict";
import { test } from "node:test";
import { classifyCrossings, clusterCentroids } from "./audit-station-spacing.mjs";
import { loadRegionRespaceGraph, medianStationChainLength } from "./respace-route-map.mjs";
import { cleanupPackDir, openPack } from "./pack-io.mjs";

const KNOWN_FREE_CROSSING_BASELINE = 1; // 벡스코(2호선×동해선) — 위 note 참고.

test("부산권 실팩: 자유 교차 ≤1(벡스코 카탈로그 한계 1건만 허용, #2068 마감)", () => {
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
      `부산권 자유 교차 ${byClass.free}건 — baseline ${KNOWN_FREE_CROSSING_BASELINE}(벡스코 카탈로그 한계 1건) 악화 금지. ` +
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
