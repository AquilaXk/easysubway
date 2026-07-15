import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "../..");
const read = (file) => readFile(path.join(root, file), "utf8");

test("Route V2 gateway는 IP·token limiter와 exact 429 계약을 소유한다", async () => {
  const nginx = await read("infra/nginx/route-v2-gateway.conf.template");

  assert.match(nginx, /rate=\$\{EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE\}r\/m;/);
  assert.match(nginx, /rate=\$\{EASYSUBWAY_ROUTE_V2_SEARCH_RATE_PER_MINUTE\}r\/m;/);
  assert.match(nginx, /limit_req_zone \$binary_remote_addr zone=route_search_ip:/);
  assert.match(nginx, /limit_req_zone \$http_authorization zone=route_search_token:/);
  assert.match(nginx, /burst=\$\{EASYSUBWAY_ROUTE_V2_SESSION_BURST\} nodelay;/);
  assert.match(nginx, /burst=\$\{EASYSUBWAY_ROUTE_V2_SEARCH_BURST\} nodelay;/);
  assert.match(nginx, /limit_req_status 429;/);
  assert.match(nginx, /access_log off;/);
  assert.match(nginx, /error_log \/dev\/stderr crit;/);
  assert.match(nginx, /limit_req_log_level info;/);
  assert.match(nginx, /error_page 429 = @route_session_rate_limited;/);
  assert.match(nginx, /error_page 429 = @route_search_rate_limited;/);
  const searchLocation = nginx.match(/location = \/api\/v2\/routes\/search \{([\s\S]*?)\n\t\}/)?.[1] ?? "";
  assert.match(searchLocation, /limit_req zone=route_search_ip burst=\$\{EASYSUBWAY_ROUTE_V2_SEARCH_BURST\} nodelay;/);
  assert.match(searchLocation, /limit_req zone=route_search_token burst=\$\{EASYSUBWAY_ROUTE_V2_SEARCH_BURST\} nodelay;/);
  assert.match(nginx, /return 429 '\{"success":false,"code":"ROUTE_RATE_LIMITED","message":"잠시 후 다시 시도"\}';/);
  assert.match(nginx, /add_header Retry-After 60 always;/);
  assert.match(nginx, /add_header Cache-Control "private, no-store" always;/);
  assert.doesNotMatch(nginx, /_internal\/route-v2\/gateway-rate-limited/);
  assert.doesNotMatch(nginx, /location @route_[a-z_]+[\s\S]*proxy_pass http:\/\/backend:8080/);
});

test("Route V2 gateway는 client origin·IP header를 제거하고 내부 origin 증명만 주입한다", async () => {
  const gateway = await read("infra/nginx/route-v2-gateway.conf.template");
  const headers = await read("infra/nginx/route-v2-proxy-headers.conf.template");
  const nginx = `${gateway}\n${headers}`;

  assert.match(gateway, /include \/tmp\/nginx-conf\.d\/route-v2-proxy-headers\.inc;/);
  assert.match(nginx, /proxy_set_header X-EasySubway-Origin-Verify \$\{EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET\};/);
  assert.match(nginx, /proxy_set_header Forwarded "";/);
  assert.match(nginx, /proxy_set_header X-Forwarded-For "";/);
  assert.match(nginx, /proxy_set_header X-Real-IP "";/);
  assert.match(nginx, /proxy_set_header CF-Connecting-IP "";/);
  assert.match(nginx, /proxy_set_header CF-Connecting-IPv6 "";/);
  assert.match(nginx, /proxy_set_header CF-Pseudo-IPv4 "";/);
  assert.match(nginx, /proxy_set_header True-Client-IP "";/);
  assert.match(nginx, /proxy_set_header X-Client-IP "";/);
  assert.doesNotMatch(nginx, /proxy_set_header X-EasySubway-Origin-Verify \$http_/);
});

test("Route V2 gateway는 trusted host proxy가 전달한 Cloudflare client IP로 session bucket을 나눈다", async () => {
  const gateway = await read("infra/nginx/route-v2-gateway.conf.template");

  assert.match(gateway, /set_real_ip_from 127\.0\.0\.1;/);
  assert.match(gateway, /set_real_ip_from \$\{EASYSUBWAY_ROUTE_V2_TRUSTED_PROXY_CIDR\};/);
  assert.match(gateway, /real_ip_header CF-Connecting-IP;/);
  assert.match(gateway, /real_ip_recursive on;/);
  assert.match(gateway, /limit_req_zone \$binary_remote_addr zone=route_session_ip/);
});

test("Compose gateway는 loopback 전용 포트와 동일 origin secret을 사용한다", async () => {
  const compose = await read("infra/docker-compose.yml");
  const block = compose.match(/\n  route-v2-gateway:\n[\s\S]*?(?=\n  [a-z0-9-]+:\n|\nvolumes:)/)?.[0] ?? "";

  assert.match(block, /image: nginx:/);
  assert.match(block, /user: "10001:10001"/);
  assert.match(block, /entrypoint: \["\/bin\/sh", "\/etc\/nginx\/route-v2-entrypoint\.sh"\]/);
  assert.match(block, /- \/tmp:rw,nosuid,nodev/);
  assert.match(block, /NGINX_ENVSUBST_OUTPUT_DIR: \/tmp\/nginx-conf\.d/);
  assert.match(block, /\.\/nginx\/nginx\.conf:\/etc\/nginx\/nginx\.conf:ro/);
  assert.match(block, /127\.0\.0\.1:\$\{EASYSUBWAY_ROUTE_V2_GATEWAY_PORT:-8081\}:8081/);
  assert.match(block, /EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET: \$\{EASYSUBWAY_ROUTE_V2_ORIGIN_SECRET\}/);
  assert.match(block, /EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE: \$\{EASYSUBWAY_ROUTE_V2_SESSION_RATE_PER_MINUTE:-5\}/);
  assert.match(block, /EASYSUBWAY_ROUTE_V2_SEARCH_RATE_PER_MINUTE: \$\{EASYSUBWAY_ROUTE_V2_SEARCH_RATE_PER_MINUTE:-10\}/);
  assert.match(block, /EASYSUBWAY_ROUTE_V2_TRUSTED_PROXY_CIDR: \$\{EASYSUBWAY_ROUTE_V2_TRUSTED_PROXY_CIDR:-172\.16\.0\.0\/12\}/);
  assert.match(block, /backend:\s*\n\s*condition: service_started/);
});

test("Route V2 gateway runtime integration probe는 privacy·bucket·identifier-free log 경계를 검증한다", async () => {
  const probe = await read("tools/test/run-route-v2-gateway-integration.sh");

  assert.match(probe, /CF-Connecting-IP: 198\.51\.100\.10/);
  assert.match(probe, /CF-Connecting-IP: 198\.51\.100\.20/);
  assert.match(probe, /CF-Connecting-IP: 198\.51\.100\.40/);
  assert.match(probe, /rawIpHeaderCount/);
  assert.match(probe, /ROUTE_RATE_LIMITED/);
  assert.match(probe, /docker logs/);
  assert.match(probe, /"scope":"session"/);
  assert.match(probe, /"scope":"search"/);
  assert.match(probe, /integration-token/);
  assert.match(probe, /rotating-token/);
  assert.match(probe, /\{"requests":12\}/);
});
