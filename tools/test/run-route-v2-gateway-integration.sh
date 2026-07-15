#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
NETWORK="easysubway-route-v2-gateway-test-$$"
BACKEND="route-v2-test-backend-$$"
GATEWAY="route-v2-test-gateway-$$"

cleanup() {
	docker rm -f "$GATEWAY" "$BACKEND" >/dev/null 2>&1 || true
	docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker network create "$NETWORK" >/dev/null
docker run -d --name "$BACKEND" --network "$NETWORK" --network-alias backend \
	-v "$ROOT/tools/ci/fixtures/route-v2-gateway-backend.mjs:/app/server.mjs:ro" \
	node:22-alpine node /app/server.mjs >/dev/null
docker run -d --name "$GATEWAY" --network "$NETWORK" --user 10001:10001 --read-only \
	--tmpfs /tmp:rw,nosuid,nodev -p 127.0.0.1::8081 \
	--entrypoint /etc/nginx/route-v2-entrypoint.sh \
	-e NGINX_ENVSUBST_FILTER=EASYSUBWAY_ \
	-e NGINX_ENVSUBST_OUTPUT_DIR=/tmp/nginx-conf.d \
	-e EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET=integration-origin-secret \
	-e EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE=5 \
	-e EASYSUBWAY_ROUTE_V2_SESSION_BURST=2 \
	-e EASYSUBWAY_ROUTE_V2_SEARCH_RATE_PER_MINUTE=10 \
	-e EASYSUBWAY_ROUTE_V2_SEARCH_BURST=3 \
	-e EASYSUBWAY_ROUTE_V2_TRUSTED_PROXY_CIDR=172.16.0.0/12 \
	-v "$ROOT/infra/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
	-v "$ROOT/infra/nginx/route-v2-entrypoint.sh:/etc/nginx/route-v2-entrypoint.sh:ro" \
	-v "$ROOT/infra/nginx/route-v2-gateway.conf.template:/etc/nginx/templates/default.conf.template:ro" \
	-v "$ROOT/infra/nginx/route-v2-proxy-headers.conf.template:/etc/nginx/templates/route-v2-proxy-headers.inc.template:ro" \
	nginx:1.28.0-alpine-slim nginx -g 'daemon off;' >/dev/null

PORT_LINE=$(docker port "$GATEWAY" 8081/tcp)
PORT=${PORT_LINE##*:}
BASE="http://127.0.0.1:$PORT"
TMP_BODY="${TMPDIR:-/tmp}/route-v2-gateway-body-$$"
TMP_HEADERS="${TMPDIR:-/tmp}/route-v2-gateway-headers-$$"
TMP_LOG="${TMPDIR:-/tmp}/route-v2-gateway-log-$$"
trap 'rm -f "$TMP_BODY" "$TMP_HEADERS" "$TMP_LOG"; cleanup' EXIT INT TERM

ready=false
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	if docker exec "$BACKEND" wget -qO- http://127.0.0.1:8080/probe >/dev/null 2>&1 \
		&& curl -sS -o /dev/null "$BASE/"; then
		ready=true
		break
	fi
	sleep 0.2
done
[ "$ready" = true ]

BODY=$(curl -fsS -H 'CF-Connecting-IP: 198.51.100.10' -H 'True-Client-IP: 198.51.100.11' "$BASE/api/v2/routes/session")
[ "$BODY" = '{"rawIpHeaderCount":0,"originVerified":true}' ]

for attempt in 1 2; do
	curl -fsS -o /dev/null -H 'CF-Connecting-IP: 198.51.100.10' "$BASE/api/v2/routes/session"
done
STATUS=$(curl -sS -D "$TMP_HEADERS" -o "$TMP_BODY" -w '%{http_code}' -H 'CF-Connecting-IP: 198.51.100.10' "$BASE/api/v2/routes/session")
[ "$STATUS" = 429 ]
[ "$(tr -d '\n' < "$TMP_BODY")" = '{"success":false,"code":"ROUTE_RATE_LIMITED","message":"잠시 후 다시 시도"}' ]
rg -qi '^Retry-After: 60' "$TMP_HEADERS"
rg -qi '^Cache-Control: private, no-store' "$TMP_HEADERS"

curl -fsS -o /dev/null -H 'CF-Connecting-IP: 198.51.100.20' "$BASE/api/v2/routes/session"

for client_suffix in 31 32 33 34; do
	curl -fsS -o /dev/null \
		-H "CF-Connecting-IP: 198.51.100.$client_suffix" \
		-H 'Authorization: Bearer integration-token' \
		"$BASE/api/v2/routes/search"
done
STATUS=$(curl -sS -o "$TMP_BODY" -w '%{http_code}' \
	-H 'CF-Connecting-IP: 198.51.100.35' \
	-H 'Authorization: Bearer integration-token' \
	"$BASE/api/v2/routes/search")
[ "$STATUS" = 429 ]
[ "$(tr -d '\n' < "$TMP_BODY")" = '{"success":false,"code":"ROUTE_RATE_LIMITED","message":"잠시 후 다시 시도"}' ]

for attempt in 1 2 3 4; do
	curl -fsS -o /dev/null \
		-H 'CF-Connecting-IP: 198.51.100.40' \
		-H "Authorization: Bearer rotating-token-$attempt" \
		"$BASE/api/v2/routes/search"
done
STATUS=$(curl -sS -o "$TMP_BODY" -w '%{http_code}' \
	-H 'CF-Connecting-IP: 198.51.100.40' \
	-H 'Authorization: Bearer rotating-token-5' \
	"$BASE/api/v2/routes/search")
[ "$STATUS" = 429 ]
[ "$(tr -d '\n' < "$TMP_BODY")" = '{"success":false,"code":"ROUTE_RATE_LIMITED","message":"잠시 후 다시 시도"}' ]

sleep 1
docker logs "$GATEWAY" > "$TMP_LOG" 2>&1
[ "$(rg -c '"scope":"session"' "$TMP_LOG")" = 1 ]
[ "$(rg -c '"scope":"search"' "$TMP_LOG")" = 2 ]
! rg -q '198\.51\.100\.|integration-token|rotating-token' "$TMP_LOG"
BACKEND_PROBE=$(docker exec "$BACKEND" wget -qO- http://127.0.0.1:8080/probe)
[ "$BACKEND_PROBE" = '{"requests":12}' ]

echo "Route V2 gateway integration passed: trusted-IP and token buckets, direct exact 429, stripped IP headers, identifier-free limiter logs"
