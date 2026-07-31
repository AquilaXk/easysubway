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
	assert.match(html, /<fieldset class="language-switch" aria-label="언어 선택"/);
	assert.doesNotMatch(html, /role="group"/);
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

test("공개 랜딩은 승인된 실제 앱 화면 2종을 self-host한다", () => {
	for (const file of ["route-map.png", "station-detail.png"]) {
		assert.ok(existsSync(`${staticRoot}/images/landing/${file}`), `${file} 정적 에셋이 필요하다`);
		assert.match(html, new RegExp(`/images/landing/${file.replace(".", "\\.")}`));
		const bytes = readFileSync(`${staticRoot}/images/landing/${file}`);
		assert.deepEqual(bytes.subarray(0, 8), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
		assert.equal(bytes.subarray(12, 16).toString("ascii"), "IHDR");
		assert.deepEqual([bytes.readUInt32BE(16), bytes.readUInt32BE(20)], [1080, 2340]);
	}
	assert.doesNotMatch(html, /\/images\/landing\/accessible-route\.png/);
	const screenshots = [...html.matchAll(/<img\b[^>]*src="\/images\/landing\/[^>]+>/g)].map(([tag]) => tag);
	assert.equal(screenshots.length, 5);
	for (const tag of screenshots) {
		assert.match(tag, /width="1080" height="2340"[^>]*decoding="async"/);
		assert.match(tag, /data-alt-ko="[^"]+" data-alt-en="[^"]+"/);
	}
	assert.equal(screenshots.filter((tag) => tag.includes('loading="lazy"')).length, 4);
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
	assert.match(css, /\.device\s*\{[^}]*aspect-ratio:\s*1080\s*\/\s*2340/);
	assert.match(css, /\.device img\s*\{[^}]*object-fit:\s*contain/);
	assert.doesNotMatch(css, /\.device--map img\s*\{/);
	assert.doesNotMatch(css, /object-fit:\s*cover|width:\s*122%|height:\s*122%/);
	for (const selector of ["device--hero", "wall-device--map", "wall-device--station"]) {
		assert.doesNotMatch(css, new RegExp(`\\.${selector}\\s*\\{[^}]*\\b(?:right|left):\\s*-\\d`));
	}
	assert.match(css, /\.feature-device--right\s*\{[^}]*right:\s*55px/);
	assert.match(css, /\.process-flow\s*\{[^}]*position:\s*absolute[^}]*\}[\s\S]*\.process-lead\s*\{[^}]*max-width/);
	assert.match(css, /@media\s*\(max-width:\s*900px\)[\s\S]*\.process-flow\s*\{\s*top:\s*710px/);
	assert.match(css, /@media\s*\(max-width:\s*720px\)[\s\S]*\.process-flow[\s\S]*\.feature-device/);
	assert.match(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)/);
});

test("언어 전환은 html lang과 aria-pressed를 함께 갱신한다", () => {
	assert.ok(existsSync(`${staticRoot}/js/landing.js`), "landing.js가 필요하다");
	const script = readFileSync(`${staticRoot}/js/landing.js`, "utf8");
	assert.match(script, /document\.documentElement\.lang\s*=\s*language/);
	assert.match(script, /setAttribute\("aria-pressed"/);
	assert.match(script, /querySelectorAll\("\[data-alt-ko\]\[data-alt-en\]"\)/);
	assert.match(script, /image\.alt\s*=\s*language\s*===\s*"en"\s*\?\s*image\.dataset\.altEn\s*:\s*image\.dataset\.altKo/);
	assert.match(script, /image\.lang\s*=\s*language/);
	assert.doesNotMatch(script, /localStorage|sessionStorage|cookie/i);
});
