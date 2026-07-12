package com.easysubway.admin.web;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("관리자 디자인 가드")
class AdminDesignGuardTest {

	private static final Path ROOT = Path.of("..").toAbsolutePath().normalize();

	private static final List<String> CSS_FILES = List.of(
		"backend/src/main/resources/static/css/admin-tokens.css",
		"backend/src/main/resources/static/css/admin-v3.css",
		"backend/src/main/resources/static/css/operator-v3.css");

	// 초록/청록 계열(및 이전 무채색·상태 리터럴) 하드코딩 금지 목록. 대소문자 무시.
	private static final Pattern FORBIDDEN_HEX = Pattern.compile(
		"#(?:0f6b52|4fcfa9|123a37|0c2b28|1f6b45|eef4f1|0f2730|16302f|5b6f6d|8a9b98"
			+ "|8a5a00|b3402c|f5f6f6|e4e8e7|d3dbd9|f6f8f7|2a2f31|1a1d1e|c8d3dc|8a9aa0"
			+ "|eef1f2|1f6f6a|1f7a44|e4f4ea|2456b3|eef4ff|5f6b7a|384250|eef1f5|7c949a)\\b",
		Pattern.CASE_INSENSITIVE);

	// box-shadow는 none 또는 var(--admin-shadow-card) 만 허용, 그 외 raw 값 금지.
	private static final Pattern BOX_SHADOW = Pattern.compile(
		"box-shadow\\s*:\\s*([^;]+)", Pattern.CASE_INSENSITIVE);
	private static final Pattern BOX_SHADOW_ALLOWED = Pattern.compile(
		"^(none\\b|var\\(--admin-shadow-card\\))", Pattern.CASE_INSENSITIVE);

	// border-radius 리터럴 px 값. 9px 이상은 금지(단 999px 이상 캡슐은 예외).
	private static final Pattern BORDER_RADIUS_PX = Pattern.compile(
		"border-radius\\s*:\\s*([^;]*)", Pattern.CASE_INSENSITIVE);
	private static final Pattern PX_LITERAL = Pattern.compile("(\\d+)px");

	@Test
	@DisplayName("금지된 초록·청록 계열 hex가 없다")
	void 금지된_초록청록_계열_hex가_없다() throws IOException {
		List<String> violations = new ArrayList<>();
		for (String path : CSS_FILES) {
			String[] lines = read(path).split("\n", -1);
			for (int i = 0; i < lines.length; i++) {
				Matcher m = FORBIDDEN_HEX.matcher(lines[i]);
				while (m.find()) {
					violations.add(path + ":" + (i + 1) + ": " + m.group());
				}
			}
		}
		assertThat(violations)
			.as("금지된 초록·청록 계열 hex 하드코딩(파일:라인:값): %s", violations)
			.isEmpty();
	}

	@Test
	@DisplayName("none이 아닌 box-shadow 선언이 없다")
	void none이_아닌_box_shadow_선언이_없다() throws IOException {
		List<String> violations = new ArrayList<>();
		for (String path : CSS_FILES) {
			String[] lines = read(path).split("\n", -1);
			for (int i = 0; i < lines.length; i++) {
				Matcher m = BOX_SHADOW.matcher(lines[i]);
				if (m.find()) {
					String value = m.group(1).trim();
					if (!BOX_SHADOW_ALLOWED.matcher(value).find()) {
						violations.add(path + ":" + (i + 1) + ": " + value);
					}
				}
			}
		}
		assertThat(violations)
			.as("허용되지 않은 box-shadow(파일:라인:값): %s", violations)
			.isEmpty();
	}

	@Test
	@DisplayName("border-radius 9px 이상 리터럴이 없다")
	void border_radius_9px_이상_리터럴이_없다() throws IOException {
		List<String> violations = new ArrayList<>();
		for (String path : CSS_FILES) {
			String[] lines = read(path).split("\n", -1);
			for (int i = 0; i < lines.length; i++) {
				Matcher decl = BORDER_RADIUS_PX.matcher(lines[i]);
				while (decl.find()) {
					Matcher px = PX_LITERAL.matcher(decl.group(1));
					while (px.find()) {
						int n = Integer.parseInt(px.group(1));
						if (n >= 9 && n < 999) {
							violations.add(path + ":" + (i + 1) + ": " + px.group());
						}
					}
				}
			}
		}
		assertThat(violations)
			.as("border-radius 9px 이상 리터럴(파일:라인:값): %s", violations)
			.isEmpty();
	}

	private static String read(String path) throws IOException {
		return Files.readString(ROOT.resolve(path));
	}
}
