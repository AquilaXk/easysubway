package com.easysubway.admin.metric.domain;

import java.util.List;

/**
 * 일별 지표 스냅샷(#1739) 키. 대시보드 즉석 계산과 같은 소스에서 뽑아 "정합"을 보장한다.
 *
 * <p>값 단위: 건수는 개수, 소요는 분, 비율은 퍼센트(0~100).
 */
public final class AdminMetricKeys {

	public static final String REPORTS_RECENT_24H = "reports.recent_24h";
	public static final String REPORTS_PENDING = "reports.pending";
	public static final String REPORTS_PROCESSING_AVG_MINUTES = "reports.processing_avg_minutes";
	public static final String FACILITIES_NEEDS_VERIFICATION = "facilities.needs_verification";
	public static final String FACILITIES_DELAYED = "facilities.delayed";
	public static final String ROUTE_SEARCHES = "route.searches";
	public static final String ROUTE_BLOCKED_RATE = "route.blocked_rate";
	public static final String PUSH_ATTEMPTED = "push.attempted";
	public static final String PUSH_FAILED = "push.failed";
	public static final String API_ERROR_RATE = "api.error_rate";
	public static final String USERS_ACTIVE = "users.active";

	private static final List<String> ALL = List.of(
		REPORTS_RECENT_24H,
		REPORTS_PENDING,
		REPORTS_PROCESSING_AVG_MINUTES,
		FACILITIES_NEEDS_VERIFICATION,
		FACILITIES_DELAYED,
		ROUTE_SEARCHES,
		ROUTE_BLOCKED_RATE,
		PUSH_ATTEMPTED,
		PUSH_FAILED,
		API_ERROR_RATE,
		USERS_ACTIVE
	);

	private AdminMetricKeys() {
	}

	public static List<String> all() {
		return ALL;
	}

	public static boolean isKnown(String metricKey) {
		return ALL.contains(metricKey);
	}
}
