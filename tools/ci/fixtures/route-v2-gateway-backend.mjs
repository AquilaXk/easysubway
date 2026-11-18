import http from "node:http";

let backendRequests = 0;
const rawIpHeaders = [
  "forwarded",
  "x-forwarded-for",
  "x-real-ip",
  "cf-connecting-ip",
  "cf-connecting-ipv6",
  "cf-pseudo-ipv4",
  "true-client-ip",
  "x-client-ip",
];

http.createServer((request, response) => {
  if (request.url === "/probe") {
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({ requests: backendRequests }));
    return;
  }
  backendRequests += 1;
  const rawIpHeaderCount = rawIpHeaders.filter((name) => request.headers[name] !== undefined).length;
  response.writeHead(200, {
    "cache-control": "private, no-store",
    "content-type": "application/json",
  });
  response.end(JSON.stringify({
    rawIpHeaderCount,
    originVerified: request.headers["x-easysubway-origin-verify"] === "integration-origin-secret",
  }));
}).listen(8080, "0.0.0.0");
