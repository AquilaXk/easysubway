#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
NETWORK="easysubway-route-v2-gateway-test-$$"
BACKEND="route-v2-test-backend-$$"
GATEWAY="route-v2-test-gateway-$$"
GATEWAY_READY_ATTEMPTS="${GATEWAY_READY_ATTEMPTS:-100}"
case "$GATEWAY_READY_ATTEMPTS" in
	''|*[!0-9]*|0)
		echo "GATEWAY_READY_ATTEMPTS must be a positive integer" >&2
		exit 2
		;;
esac

cleanup() {
	docker rm -f "$GATEWAY" "$BACKEND" >/dev/null 2>&1 || true
	docker network rm "$NETWORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

docker network create "$NETWORK" >/dev/null
docker run -d --name "$BACKEND" --network "$NETWORK" --network-alias backend \
	-v "$ROOT/tools/ci/fixtures/route-v2-gateway-backend.mjs:/app/server.mjs:ro" \
	node:22-alpine node /app/server.mjs >/dev/null

start_gateway() {
	origin_secret="$1"
	docker run -d --name "$GATEWAY" --network "$NETWORK" --user 10001:10001 --read-only \
		--tmpfs /tmp:rw,nosuid,nodev -p 127.0.0.1::8081 \
		--entrypoint /etc/nginx/route-v2-entrypoint.sh \
		-e NGINX_ENVSUBST_FILTER=EASYSUBWAY_ \
		-e NGINX_ENVSUBST_OUTPUT_DIR=/tmp/nginx-conf.d \
		-e "EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET=$origin_secret" \
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
}

set_gateway_base() {
	PORT_LINE=$(docker port "$GATEWAY" 8081/tcp)
	PORT=${PORT_LINE##*:}
	BASE="http://127.0.0.1:$PORT"
}

wait_gateway() {
	ready=false
	attempt=1
	while [ "$attempt" -le "$GATEWAY_READY_ATTEMPTS" ]; do
		if docker exec "$BACKEND" wget -qO- http://127.0.0.1:8080/probe >/dev/null 2>&1 \
			&& curl -sS -o /dev/null "$BASE/"; then
			ready=true
			break
		fi
		sleep 0.2
		attempt=$((attempt + 1))
	done
	if [ "$ready" != true ]; then
		echo "gateway readiness timed out after $GATEWAY_READY_ATTEMPTS attempts" >&2
		docker logs "$GATEWAY" >&2 || true
		docker logs "$BACKEND" >&2 || true
		return 1
	fi
}

start_gateway ""
set_gateway_base
wait_gateway
BODY=$(curl -fsS "$BASE/api/v2/routes/session")
[ "$BODY" = '{"rawIpHeaderCount":0,"originVerified":false}' ]
docker rm -f "$GATEWAY" >/dev/null

start_gateway "integration-origin-secret"
set_gateway_base
TMP_BODY="${TMPDIR:-/tmp}/route-v2-gateway-body-$$"
TMP_HEADERS="${TMPDIR:-/tmp}/route-v2-gateway-headers-$$"
TMP_LOG="${TMPDIR:-/tmp}/route-v2-gateway-log-$$"
trap 'rm -f "$TMP_BODY" "$TMP_HEADERS" "$TMP_LOG"; cleanup' EXIT INT TERM

wait_gateway

BODY=$(curl -fsS -D "$TMP_HEADERS" -H 'CF-Connecting-IP: 198.51.100.10' -H 'True-Client-IP: 198.51.100.11' "$BASE/api/v2/routes/session")
[ "$BODY" = '{"rawIpHeaderCount":0,"originVerified":true}' ]
grep -Eqi '^Cache-Control: private, no-store' "$TMP_HEADERS" || {
	echo "session success response must remain private, no-store" >&2
	exit 1
}

for attempt in 1 2; do
	curl -fsS -o /dev/null -H 'CF-Connecting-IP: 198.51.100.10' "$BASE/api/v2/routes/session"
	sleep 0.5
done
STATUS=$(curl -sS -D "$TMP_HEADERS" -o "$TMP_BODY" -w '%{http_code}' -H 'CF-Connecting-IP: 198.51.100.10' "$BASE/api/v2/routes/session")
[ "$STATUS" = 429 ]
[ "$(tr -d '\n' < "$TMP_BODY")" = '{"success":false,"code":"ROUTE_RATE_LIMITED","message":"잠시 후 다시 시도"}' ]
grep -Eqi '^Retry-After: 60' "$TMP_HEADERS"
grep -Eqi '^Cache-Control: private, no-store' "$TMP_HEADERS"

curl -fsS -o /dev/null -H 'CF-Connecting-IP: 198.51.100.20' "$BASE/api/v2/routes/session"

for client_suffix in 31 32 33 34; do
	curl -fsS -D "$TMP_HEADERS" -o /dev/null \
		-H "CF-Connecting-IP: 198.51.100.$client_suffix" \
		-H 'Authorization: Bearer integration-token' \
		"$BASE/api/v2/routes/search"
	sleep 0.5
done
grep -Eqi '^Cache-Control: private, no-store' "$TMP_HEADERS" || {
	echo "search success response must remain private, no-store" >&2
	exit 1
}
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
	sleep 0.5
done
STATUS=$(curl -sS -o "$TMP_BODY" -w '%{http_code}' \
	-H 'CF-Connecting-IP: 198.51.100.40' \
	-H 'Authorization: Bearer rotating-token-5' \
	"$BASE/api/v2/routes/search")
[ "$STATUS" = 429 ]
[ "$(tr -d '\n' < "$TMP_BODY")" = '{"success":false,"code":"ROUTE_RATE_LIMITED","message":"잠시 후 다시 시도"}' ]

sleep 1
docker logs "$GATEWAY" > "$TMP_LOG" 2>&1
[ "$(grep -Ec '"scope":"session"' "$TMP_LOG")" = 1 ]
[ "$(grep -Ec '"scope":"search"' "$TMP_LOG")" = 2 ]
! grep -Eq '198\.51\.100\.|integration-token|rotating-token' "$TMP_LOG"
BACKEND_PROBE=$(docker exec "$BACKEND" wget -qO- http://127.0.0.1:8080/probe)
[ "$BACKEND_PROBE" = '{"requests":13}' ]

echo "Route V2 gateway integration passed: trusted-IP and token buckets, direct exact 429, stripped IP headers, identifier-free limiter logs"
