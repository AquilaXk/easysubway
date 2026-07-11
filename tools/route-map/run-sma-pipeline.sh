#!/usr/bin/env bash
# #1950 수도권 정본 도식(easy-subway-sma-v*) 반복 파이프라인 — 한 줄 재실행.
#
# 오너가 v(N+1) SVG를 주면:
#   1) 새 SVG를 tools/route-map/route-map-defs/svg-sources/easy-subway-sma-v<N>.svg로 복사
#   2) tools/route-map/run-sma-pipeline.sh <svg경로> [이전버전추출JSON]
# 하면 추출→canonical 정합→track→투영→enrich(팩 재빌드)까지 재실행하고,
# 이전 추출 JSON을 주면 버전 diff 리포트까지 산출한다.
#
# 환경: Chrome/Chromium 필요(추출기). CHROME_PATH로 지정 가능.
set -euo pipefail

SVG="${1:?사용: run-sma-pipeline.sh <svg경로> [이전버전추출JSON]}"
PREV_GEOM="${2:-}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PACK="apps/mobile/assets/datapacks/capital.sqlite.gz"
INDEX="apps/mobile/assets/datapacks/index.json"
WORK="${SMA_WORK:-$(mktemp -d)}"
GEOM="$WORK/sma-geom.json"
TRACKS="$WORK/sma-tracks.json"
TRACKS24="$WORK/sma-tracks24.json"
SEOHAE="$WORK/seohae-paths.json"

cd "$ROOT"

echo "[1/7] geometry 추출(결정적: 역 노드 + 8선형 path vertex)"
node tools/route-map/extract-svg-geometry.mjs "$SVG" --region 수도권 > "$GEOM"

echo "[2/7] canonical 정합 + route_map_positions 좌표 교체(미매핑 0 게이트)"
node tools/route-map/apply-sma-svg-positions.mjs --extraction "$GEOM" --pack "$PACK" --index "$INDEX"

echo "[3/7] 서해선(fill-only, stroke 없음) track = 역 dot 8선형화 결과에서 추출"
node tools/route-map/octolinearize-line-tracks.mjs --region 수도권 --line "수도권 서해선" --pack "$PACK"
SEOHAE_LINE_ID=$(node -e "const{gunzipSync}=require('node:zlib');const fs=require('node:fs');const{DatabaseSync}=require('node:sqlite');const t=fs.mkdtempSync('/tmp/sma-');fs.writeFileSync(t+'/p.sqlite',gunzipSync(fs.readFileSync('$PACK')));const db=new DatabaseSync(t+'/p.sqlite');console.log(db.prepare('SELECT id FROM lines WHERE name_ko=?').get('수도권 서해선').id);db.close();")
node -e "const{gunzipSync}=require('node:zlib');const fs=require('node:fs');const{DatabaseSync}=require('node:sqlite');const t=fs.mkdtempSync('/tmp/sma-');fs.writeFileSync(t+'/p.sqlite',gunzipSync(fs.readFileSync('$PACK')));const db=new DatabaseSync(t+'/p.sqlite');const r=db.prepare('SELECT path FROM route_map_line_tracks WHERE region=? AND line_id=?').all('수도권','$SEOHAE_LINE_ID');fs.writeFileSync('$SEOHAE',JSON.stringify(r.map(x=>x.path)));db.close();"

echo "[4/7] 노선 track 생성(SVG 색→슬러그→line_id 결정적 배정 + 8선형 stitch) + 서해선 주입"
node tools/route-map/build-sma-tracks.mjs --geometry "$GEOM" --pack "$PACK" --region 수도권 --out "$TRACKS" --stitch-tolerance 40
node -e "const fs=require('node:fs');const d=JSON.parse(fs.readFileSync('$TRACKS','utf8'));const p=JSON.parse(fs.readFileSync('$SEOHAE','utf8'));d.lines=d.lines.filter(l=>l.lineId!=='$SEOHAE_LINE_ID');d.lines.push({lineId:'$SEOHAE_LINE_ID',svgColor:'',trackCount:p.length,paths:p});d.lineCount=d.lines.length;fs.writeFileSync('$TRACKS24',JSON.stringify(d,null,1));"

echo "[5/7] track 팩 반영 + 역 노드 track 투영(투영 게이트)"
node tools/route-map/apply-route-map-line-tracks.mjs --pack "$PACK" --index "$INDEX" --tracks "$TRACKS24"
node tools/route-map/project-nodes-to-tracks.mjs --region 수도권 --pack "$PACK" --index "$INDEX"

echo "[6/7] 재간격(respace: p95/p5 균일화 + 라벨 겹침 완화) + track 8선형 잔차 스냅 + enrich"
node tools/route-map/respace-route-map.mjs --region 수도권 --pack "$PACK" --index "$INDEX" | head -1
node tools/route-map/snap-tracks-octolinear.mjs --region 수도권 --pack "$PACK" --index "$INDEX"
node tools/route-map/enrich-capital-route-map-layer.mjs --pack "$PACK" --index "$INDEX" --region 수도권 >/dev/null

echo "[7/7] 게이트 실측"
node tools/route-map/audit-station-spacing.mjs | head -2
node tools/route-map/audit-transfer-groups.mjs | head -2

if [[ -n "$PREV_GEOM" ]]; then
  echo "[diff] v(N)↔v(N+1) 변경 리포트"
  node tools/route-map/diff-sma-versions.mjs --old "$PREV_GEOM" --new "$GEOM"
fi

echo "완료. GEOM=$GEOM (다음 버전 diff 기준으로 보관)"
