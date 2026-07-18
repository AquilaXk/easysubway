package com.easysubway.collection.application.service;

import java.util.regex.Pattern;

final class DataCollectionFailureDetailSanitizer {

	static final int MAX_LENGTH = 500;

	private static final String PROTECTED_DETAIL = "상세 오류는 보호 정책에 따라 생략되었습니다.";
	private static final Pattern URL_QUERY = Pattern.compile("(?i)https?://\\S*\\?\\S*");
	private static final Pattern CREDENTIAL = Pattern.compile(
		"(?i)[\"']?\\b(?:authorization|cookie|set-cookie|password|passwd|secret|token|access[_-]?key|api[_-]?key|credential|client[_-]?secret)\\b[\"']?\\s*[:=]"
	);
	private static final Pattern AUTHORIZATION_VALUE = Pattern.compile("(?i)\\b(?:bearer|basic)\\s+[a-z0-9._~+/=-]+");
	private static final Pattern RAW_BODY = Pattern.compile("(?i)\\b(?:request|response|provider)?\\s*body\\s*[:=]");

	private DataCollectionFailureDetailSanitizer() {
	}

	static String operatorSafe(Throwable failure) {
		return operatorSafe(failure, failure == null ? "배치 처리 실패" : failure.getClass().getSimpleName());
	}

	static String operatorSafe(Throwable failure, String fallback) {
		String type = failure == null ? "BatchExecution" : failure.getClass().getSimpleName();
		String rawMessage = failure == null ? fallback : failure.getMessage();
		String normalized = normalize(rawMessage == null || rawMessage.isBlank() ? type : rawMessage);
		if (containsProtectedDetail(normalized)) {
			return type + ": " + PROTECTED_DETAIL;
		}
		return truncate(normalized);
	}

	private static String normalize(String value) {
		return value.replaceAll("\\s+", " ").trim();
	}

	private static boolean containsProtectedDetail(String value) {
		return URL_QUERY.matcher(value).find()
			|| CREDENTIAL.matcher(value).find()
			|| AUTHORIZATION_VALUE.matcher(value).find()
			|| RAW_BODY.matcher(value).find();
	}

	private static String truncate(String value) {
		if (value.length() <= MAX_LENGTH) {
			return value;
		}
		int end = MAX_LENGTH - 1;
		if (Character.isHighSurrogate(value.charAt(end - 1))) {
			end--;
		}
		return value.substring(0, end) + "…";
	}
}
