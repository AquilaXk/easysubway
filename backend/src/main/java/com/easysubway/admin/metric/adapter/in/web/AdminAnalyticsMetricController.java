package com.easysubway.admin.metric.adapter.in.web;

import com.easysubway.admin.metric.application.service.AdminMetricQueryService;
import com.easysubway.admin.metric.application.service.AdminMetricQueryService.AdminMetricChart;
import com.easysubway.admin.metric.application.service.AdminMetricQueryService.AdminMetricComparison;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 경로·사용 분석 데이터 API(#1744). 분석 화면(경로 검색·피드백·사용 현황)이 소비할 시계열과
 * 기간 비교(전 기간 대비 증감)를 돌려준다. 대시보드 요약 API({@code /admin/dashboard/metrics})와
 * 같은 {@link AdminMetricQueryService}를 재사용해 수치 정합을 보장한다.
 *
 * <p>권한은 /admin/** 기본 규칙(ADMIN_VIEW)을 따른다. 기간 전환은 이 엔드포인트 재호출로 부분 갱신한다.
 */
@RestController
class AdminAnalyticsMetricController {

	private final AdminMetricQueryService metricQueryService;

	AdminAnalyticsMetricController(AdminMetricQueryService metricQueryService) {
		this.metricQueryService = metricQueryService;
	}

	@GetMapping("/admin/analytics/metrics")
	AdminMetricChart metrics(
		@RequestParam(name = "keys", required = false) List<String> keys,
		@RequestParam(name = "days", defaultValue = "7") int days
	) {
		return metricQueryService.chart(keys == null ? List.of() : keys, days);
	}

	@GetMapping("/admin/analytics/comparison")
	List<AdminMetricComparison> comparison(
		@RequestParam(name = "keys", required = false) List<String> keys,
		@RequestParam(name = "days", defaultValue = "7") int days
	) {
		return metricQueryService.compare(keys == null ? List.of() : keys, days);
	}
}
