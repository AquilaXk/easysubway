package com.easysubway.collection.application.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

@DisplayName("데이터 수집 실패 상세 정규화")
class DataCollectionFailureDetailSanitizerTest {

	@ParameterizedTest(name = "{index}: 보호 대상 실패 상세")
	@ValueSource(strings = {
		"GET https://provider.example/v1/stations?mode=full",
		"credential=provider-secret",
		"{\"token\":\"body-secret\"}",
		"response body={\"error\":\"provider payload\"}"
	})
	@DisplayName("URL query와 credential과 token과 body는 고정 안전 문구로 대체한다")
	void replacesProtectedFailureShapes(String rawFailure) {
		String safeDetail = DataCollectionFailureDetailSanitizer.operatorSafe(
			new IllegalStateException(rawFailure)
		);

		assertThat(safeDetail)
			.contains("보호 정책")
			.doesNotContain(rawFailure);
	}

	@Test
	@DisplayName("일반 실패 상세도 DB 한도보다 짧은 500자로 제한한다")
	void truncatesOrdinaryFailureDetail() {
		String safeDetail = DataCollectionFailureDetailSanitizer.operatorSafe(
			new IllegalStateException("x".repeat(1_001))
		);

		assertThat(safeDetail)
			.hasSize(DataCollectionFailureDetailSanitizer.MAX_LENGTH)
			.endsWith("…");
	}
}
