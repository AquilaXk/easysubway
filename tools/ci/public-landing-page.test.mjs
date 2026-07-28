import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

const staticRoot = "backend/src/main/resources/static";
const html = readFileSync(`${staticRoot}/index.html`, "utf8");

test("공개 랜딩은 한국어 기본값과 접근 가능한 KR/EN 전환 계약을 노출한다", () => {
	assert.match(html, /<html lang="ko"/);
	assert.match(html, /href="#main"/);
	assert.match(html, /data-language="ko"/);
	assert.match(html, /data-language="en"/);
	assert.match(html, /aria-pressed="true"/);
	assert.match(html, /aria-pressed="false"/);
	assert.match(html, /class="language-switch" role="group"/);
	assert.match(html, /class="skip-link"[^>]*lang="ko"/);
	assert.match(html, /class="site-footer" lang="ko"/);
	assert.match(html, /class="kicker" lang="en">Mobility without barriers/);
	assert.match(html, /class="process-title" lang="en"/);
	assert.match(html, /class="frame wall-heading" lang="en"/);
	assert.doesNotMatch(html, /class="screen-wall" aria-label=/);
	assert.match(html, /src="\/js\/landing\.js" defer/);
	assert.doesNotMatch(html, /onclick=/);
	assert.doesNotMatch(html, /Product showcase/i);
	assert.match(html, /상록수·사당 검증 pilot/);
	assert.doesNotMatch(html, /Connected regions|Core offline route|100%|5 regions|nationwide/i);
});

test("공개 랜딩은 승인된 실제 앱 화면 3종을 self-host한다", () => {
	for (const file of ["route-map.png", "accessible-route.png", "station-detail.png"]) {
		assert.ok(existsSync(`${staticRoot}/images/landing/${file}`), `${file} 정적 에셋이 필요하다`);
		assert.match(html, new RegExp(`/images/landing/${file.replace(".", "\\.")}`));
	}
	const screenshots = [...html.matchAll(/<img\b[^>]*src="\/images\/landing\/[^>]+>/g)].map(([tag]) => tag);
	assert.equal(screenshots.length, 7);
	for (const tag of screenshots) assert.match(tag, /width="1080" height="2340"[^>]*decoding="async"/);
	assert.equal(screenshots.filter((tag) => tag.includes('loading="lazy"')).length, 6);
});

test("공개 랜딩 스타일은 공식 브랜드와 읽기 쉬운 디바이스 계약을 지킨다", () => {
	assert.ok(existsSync(`${staticRoot}/css/landing.css`), "landing.css가 필요하다");
	const css = readFileSync(`${staticRoot}/css/landing.css`, "utf8");
	for (const color of ["#5c6bc0", "#b4bcfb", "#1f2340", "#f8f9ff", "#f0f2fe"]) {
		assert.match(css.toLowerCase(), new RegExp(color));
	}
	assert.doesNotMatch(css.toLowerCase(), /#0a705a/);
	assert.match(css, /\.hero-copy\s*>\s*p\[data-copy\]/);
	assert.doesNotMatch(css, /\.hero-copy\s*>\s*p:last-child/);
	assert.match(css, /\.feature-copy h2\s*\{[^}]*font-size:\s*clamp\(33px,\s*9\.5vw,\s*43px\)/);
	assert.match(css, /\.device--map img\s*\{[^}]*width:\s*122%;[^}]*height:\s*122%/);
	assert.match(css, /\.device--route img,[\s\S]*\.device--station img[\s\S]*object-fit:\s*contain/);
	assert.match(css, /\.process-flow\s*\{[^}]*position:\s*absolute[^}]*\}[\s\S]*\.process-lead\s*\{[^}]*max-width/);
	assert.match(css, /@media\s*\(max-width:\s*720px\)[\s\S]*\.process-flow[\s\S]*\.feature-device/);
	assert.match(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)/);
});

test("언어 전환은 html lang과 aria-pressed를 함께 갱신한다", () => {
	assert.ok(existsSync(`${staticRoot}/js/landing.js`), "landing.js가 필요하다");
	const script = readFileSync(`${staticRoot}/js/landing.js`, "utf8");
	assert.match(script, /document\.documentElement\.lang\s*=\s*language/);
	assert.match(script, /setAttribute\("aria-pressed"/);
	assert.doesNotMatch(script, /localStorage|sessionStorage|cookie/i);
});
