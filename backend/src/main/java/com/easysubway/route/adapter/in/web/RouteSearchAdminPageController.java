package com.easysubway.route.adapter.in.web;

import com.easysubway.admin.metric.application.service.AdminMetricQueryService;
import com.easysubway.admin.metric.application.service.AdminMetricQueryService.AdminMetricChart;
import com.easysubway.admin.metric.application.service.AdminMetricQueryService.AdminMetricComparison;
import com.easysubway.admin.metric.domain.AdminMetricKeys;
import com.easysubway.route.application.port.in.RouteSearchDashboardUseCase;
import com.easysubway.route.domain.RouteSearchDashboardSummary;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.wimdeblauwe.htmx.spring.boot.mvc.HxRequest;
import java.util.List;
import java.util.Set;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
class RouteSearchAdminPageController {

	// 검색량은 높을수록, 차단률은 낮을수록 좋은 신호다(증감 카드 tone 판정).
	private static final Set<String> HIGHER_IS_BETTER = Set.of(AdminMetricKeys.ROUTE_SEARCHES);
	private static final List<String> TREND_KEYS =
		List.of(AdminMetricKeys.ROUTE_SEARCHES, AdminMetricKeys.ROUTE_BLOCKED_RATE);

	private final RouteSearchDashboardUseCase routeSearchDashboardUseCase;
	private final AdminMetricQueryService metricQueryService;
	private final ObjectMapper objectMapper;

	RouteSearchAdminPageController(
		RouteSearchDashboardUseCase routeSearchDashboardUseCase,
		AdminMetricQueryService metricQueryService,
		ObjectMapper objectMapper
	) {
		this.routeSearchDashboardUseCase = routeSearchDashboardUseCase;
		this.metricQueryService = metricQueryService;
		this.objectMapper = objectMapper;
	}

	@GetMapping("/admin/routes/searches/page")
	String routeSearchDashboardPage(
		@RequestParam(name = "days", defaultValue = "7") int days,
		Model model
	) {
		RouteSearchDashboardSummary summary = routeSearchDashboardUseCase.summarizeRouteSearches();
		model.addAttribute("summary", RouteSearchDashboardView.from(summary));
		populateTrends(days, model);
		return "admin/routes/searches";
	}

	// 추이·증감 부분 갱신(#1744): 기간 버튼이 이 fragment를 htmx로 다시 불러 차트·증감 카드·대체표를 갈아끼운다.
	@HxRequest
	@GetMapping("/admin/routes/searches/trends")
	String routeSearchTrends(
		@RequestParam(name = "days", defaultValue = "7") int days,
		Model model
	) {
		populateTrends(days, model);
		return "admin/routes/searches :: trends";
	}

	private void populateTrends(int days, Model model) {
		AdminMetricChart chart = metricQueryService.chart(TREND_KEYS, days);
		model.addAttribute("trendChart", chart);
		model.addAttribute("trendJson", toJson(chart));
		model.addAttribute("trendDays", chart.days());
		model.addAttribute("comparisons", metricQueryService.compare(TREND_KEYS, days)
			.stream()
			.map(ComparisonCardView::from)
			.toList());
	}

	// Chart.js가 읽을 데이터 섬(JSON). 직렬화 실패 시 빈 차트로 안전 폴백(details 표가 대체).
	private String toJson(AdminMetricChart chart) {
		try {
			return objectMapper.writeValueAsString(chart);
		} catch (JsonProcessingException exception) {
			return "{\"labels\":[],\"series\":[]}";
		}
	}

	/**
	 * 증감 요약 카드 뷰. 최근 기간 합계·증감률·개선 여부(tone)를 표시용으로 정리한다.
	 */
	record ComparisonCardView(
		String label,
		String currentLabel,
		String previousLabel,
		String deltaPercentLabel,
		String tone,
		boolean up
	) {

		static ComparisonCardView from(AdminMetricComparison comparison) {
			boolean higherIsBetter = HIGHER_IS_BETTER.contains(comparison.key());
			boolean up = comparison.delta() > 0;
			String tone = comparison.delta() == 0
				? "neutral"
				: (comparison.improved(higherIsBetter) ? "good" : "bad");
			return new ComparisonCardView(
				comparison.label(),
				formatValue(comparison.current()),
				formatValue(comparison.previous()),
				comparison.deltaPercent() == null
					? "직전 없음"
					: "%+.1f%%".formatted(comparison.deltaPercent()),
				tone,
				up
			);
		}

		private static String formatValue(double value) {
			return value == Math.rint(value) ? "%.0f".formatted(value) : "%.1f".formatted(value);
		}
	}
}
