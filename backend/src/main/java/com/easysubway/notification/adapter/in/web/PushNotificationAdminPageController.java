package com.easysubway.notification.adapter.in.web;

import com.easysubway.admin.audit.application.service.AdminAuditWriter;
import com.easysubway.admin.metric.adapter.in.web.AnalyticsComparisonCard;
import com.easysubway.admin.metric.application.service.AdminMetricQueryService;
import com.easysubway.admin.metric.application.service.AdminMetricQueryService.AdminMetricChart;
import com.easysubway.admin.metric.domain.AdminMetricKeys;
import com.easysubway.common.domain.PageResult;
import com.easysubway.common.web.pagination.EgovPaginationView;
import com.easysubway.notification.application.port.in.PushNotificationDashboardUseCase;
import com.easysubway.notification.application.port.in.PushNotificationHistoryQuery;
import com.easysubway.notification.application.port.in.PushNotificationHistoryUseCase;
import com.easysubway.notification.domain.PushNotification;
import com.easysubway.notification.domain.PushNotificationDashboardSummary;
import com.easysubway.notification.domain.PushNotificationFailureReasonCount;
import com.easysubway.notification.domain.PushNotificationStatus;
import com.easysubway.notification.domain.PushNotificationType;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.wimdeblauwe.htmx.spring.boot.mvc.HxRequest;
import jakarta.servlet.http.HttpServletRequest;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.util.UriComponentsBuilder;

@Controller
class PushNotificationAdminPageController {

	// 발송 시도는 도달(증가)이, 발송 실패는 감소가 좋은 신호다(증감 카드 tone 판정).
	private static final Set<String> HIGHER_IS_BETTER = Set.of(AdminMetricKeys.PUSH_ATTEMPTED);
	private static final List<String> TREND_KEYS =
		List.of(AdminMetricKeys.PUSH_ATTEMPTED, AdminMetricKeys.PUSH_FAILED);
	private static final String HISTORY_PATH = "/admin/notifications/push/history";

	private final PushNotificationDashboardUseCase pushNotificationDashboardUseCase;
	private final PushNotificationHistoryUseCase pushNotificationHistoryUseCase;
	private final AdminMetricQueryService metricQueryService;
	private final AdminAuditWriter auditWriter;
	private final ObjectMapper objectMapper;

	PushNotificationAdminPageController(
		PushNotificationDashboardUseCase pushNotificationDashboardUseCase,
		PushNotificationHistoryUseCase pushNotificationHistoryUseCase,
		AdminMetricQueryService metricQueryService,
		AdminAuditWriter auditWriter,
		ObjectMapper objectMapper
	) {
		this.pushNotificationDashboardUseCase = pushNotificationDashboardUseCase;
		this.pushNotificationHistoryUseCase = pushNotificationHistoryUseCase;
		this.metricQueryService = metricQueryService;
		this.auditWriter = auditWriter;
		this.objectMapper = objectMapper;
	}

	@GetMapping("/admin/notifications/push/page")
	String pushNotificationDashboardPage(
		@RequestParam(name = "days", defaultValue = "7") int days,
		@RequestParam(name = "status", required = false) PushNotificationStatus status,
		@RequestParam(name = "type", required = false) PushNotificationType type,
		@RequestParam(name = "keyword", required = false) String keyword,
		@RequestParam(name = "reason", required = false) String reason,
		@RequestParam(name = "from", required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
		@RequestParam(name = "to", required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
		@RequestParam(name = "page", required = false) Integer page,
		Authentication authentication,
		HttpServletRequest request,
		Model model
	) {
		PushNotificationDashboardSummary summary = pushNotificationDashboardUseCase.summarizePushNotifications();
		model.addAttribute("summary", PushNotificationDashboardView.from(summary));
		populateTrends(days, model);
		populateHistory(historyQuery(status, type, keyword, reason, from, to, page), authentication, request, model);
		return "admin/notifications/push";
	}

	// no-JS 발송 이력 필터: 폼 제출이 이 경로로 GET하면 이력이 채워진 풀페이지를 돌려준다.
	@GetMapping(HISTORY_PATH)
	String pushNotificationHistoryPage(
		@RequestParam(name = "status", required = false) PushNotificationStatus status,
		@RequestParam(name = "type", required = false) PushNotificationType type,
		@RequestParam(name = "keyword", required = false) String keyword,
		@RequestParam(name = "reason", required = false) String reason,
		@RequestParam(name = "from", required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
		@RequestParam(name = "to", required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
		@RequestParam(name = "page", required = false) Integer page,
		Authentication authentication,
		HttpServletRequest request,
		Model model
	) {
		return pushNotificationDashboardPage(
			7, status, type, keyword, reason, from, to, page, authentication, request, model);
	}

	// 발송 이력 부분 갱신(#1746): 필터·페이지 링크가 이 fragment를 htmx로 다시 불러 표·페이지네이션만 갈아끼운다.
	// htmx 히스토리 복원 요청은 셸을 포함한 풀페이지를 돌려줘 화면이 깨지지 않게 한다.
	@HxRequest
	@GetMapping(HISTORY_PATH)
	String pushNotificationHistoryFragment(
		@RequestParam(name = "status", required = false) PushNotificationStatus status,
		@RequestParam(name = "type", required = false) PushNotificationType type,
		@RequestParam(name = "keyword", required = false) String keyword,
		@RequestParam(name = "reason", required = false) String reason,
		@RequestParam(name = "from", required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
		@RequestParam(name = "to", required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
		@RequestParam(name = "page", required = false) Integer page,
		@RequestHeader(value = "HX-History-Restore-Request", required = false) boolean historyRestore,
		Authentication authentication,
		HttpServletRequest request,
		Model model
	) {
		if (historyRestore) {
			return pushNotificationHistoryPage(
				status, type, keyword, reason, from, to, page, authentication, request, model);
		}
		populateHistory(historyQuery(status, type, keyword, reason, from, to, page), authentication, request, model);
		return "admin/notifications/push :: historyResults";
	}

	private static PushNotificationHistoryQuery historyQuery(
		PushNotificationStatus status,
		PushNotificationType type,
		String keyword,
		String reason,
		LocalDate from,
		LocalDate to,
		Integer page
	) {
		return PushNotificationHistoryQuery.of(status, type, keyword, reason, from, to, page, null);
	}

	// 발송 이력 표준 테이블: 필터·페이지네이션이 적용된 목록을 채운다. 수신자 식별자는 마스킹되며
	// 열람은 감사에 남긴다(개인정보 최소 노출 원칙). 목록·건수·분해가 같은 질의를 공유해 정합을 보장한다.
	private void populateHistory(
		PushNotificationHistoryQuery query,
		Authentication authentication,
		HttpServletRequest request,
		Model model
	) {
		long total = pushNotificationHistoryUseCase.countPushNotifications(query);
		EgovPaginationView pageView = EgovPaginationView.from(query.page(), query.size(), total);
		PushNotificationHistoryQuery pageQuery = query.withPage(pageView.page());
		PageResult<PushNotification> historyPage = pushNotificationHistoryUseCase.searchPushNotifications(pageQuery);
		List<PushNotificationHistoryRow> rows = historyPage.items().stream()
			.map(PushNotificationHistoryRow::from)
			.toList();

		model.addAttribute("historyRows", rows);
		model.addAttribute("historyPage", pageView);
		model.addAttribute("historyTotal", total);
		model.addAttribute("historyPaginationLinks", pageView.links(HISTORY_PATH, historyParams(pageQuery)));
		model.addAttribute("historySelectedStatus", pageQuery.status());
		model.addAttribute("historySelectedType", pageQuery.type());
		model.addAttribute("historyKeyword", pageQuery.keyword());
		model.addAttribute("historyFrom", pageQuery.createdFrom());
		model.addAttribute("historyTo", pageQuery.createdTo());
		model.addAttribute("historyStatusOptions", statusOptions(pageQuery.status()));
		model.addAttribute("historyTypeOptions", typeOptions(pageQuery.type()));

		// 실패 사유별 분해(막대) + 드릴다운. 목록과 같은 필터 컨텍스트를 공유해 분해 수치 = 사유 필터 목록 건수 정합.
		List<PushNotificationFailureReasonCount> breakdown =
			pushNotificationHistoryUseCase.summarizeFailureReasons(pageQuery);
		long maxReasonCount = breakdown.stream()
			.mapToLong(PushNotificationFailureReasonCount::count)
			.max()
			.orElse(0L);
		List<FailureBreakdownBar> bars = breakdown.stream()
			.map(item -> new FailureBreakdownBar(
				item.reason(),
				item.count(),
				maxReasonCount == 0 ? 0 : Math.round(item.count() * 100.0 / maxReasonCount),
				historyReasonHref(pageQuery, item.reason()),
				item.reason().equals(pageQuery.failureReason())))
			.toList();
		model.addAttribute("failureBreakdown", bars);
		model.addAttribute("hasReasonFilter", pageQuery.hasFailureReason());
		model.addAttribute("selectedReason", pageQuery.failureReason());
		model.addAttribute("clearReasonHref", historyReasonHref(pageQuery, null));

		// 마스킹된 수신자 식별자를 노출하는 조회라 열람 자체를 감사에 남긴다(원문·free-text 없음).
		auditWriter.privacyRead(
			authentication,
			request,
			"PUSH_NOTIFICATION_HISTORY",
			"list",
			"VIEW_PUSH_HISTORY",
			"업무 맥락: 푸시 발송 이력 조회(수신자 식별자 마스킹)"
		);
	}

	// 페이지네이션·필터 링크가 현재 필터를 유지하도록 활성 파라미터만 전달한다(널·빈 값은 생략).
	private static Map<String, Object> historyParams(PushNotificationHistoryQuery query) {
		Map<String, Object> params = new LinkedHashMap<>();
		params.put("status", query.status());
		params.put("type", query.type());
		params.put("keyword", query.keyword());
		params.put("reason", query.failureReason());
		params.put("from", query.createdFrom());
		params.put("to", query.createdTo());
		return params;
	}

	// 사유 드릴다운 링크: 현재 필터(상태·유형·검색·기간)를 유지하고 reason만 설정/해제한다(페이지는 처음으로).
	private static String historyReasonHref(PushNotificationHistoryQuery query, String reason) {
		Map<String, Object> params = new LinkedHashMap<>(historyParams(query));
		params.put("reason", reason);
		UriComponentsBuilder builder = UriComponentsBuilder.fromPath(HISTORY_PATH);
		params.forEach((name, value) -> {
			if (value != null && !value.toString().isBlank()) {
				builder.queryParam(name, value);
			}
		});
		return builder.build().encode().toUriString();
	}

	record FailureBreakdownBar(String reason, long count, long percent, String href, boolean active) {
	}

	private static List<FilterOption> statusOptions(PushNotificationStatus selected) {
		List<FilterOption> options = new java.util.ArrayList<>();
		options.add(new FilterOption("", "상태 전체", selected == null));
		for (PushNotificationStatus status : PushNotificationStatus.values()) {
			options.add(new FilterOption(
				status.name(), PushNotificationHistoryRow.statusLabel(status), status == selected));
		}
		return options;
	}

	private static List<FilterOption> typeOptions(PushNotificationType selected) {
		List<FilterOption> options = new java.util.ArrayList<>();
		options.add(new FilterOption("", "유형 전체", selected == null));
		for (PushNotificationType type : PushNotificationType.values()) {
			options.add(new FilterOption(
				type.name(), PushNotificationHistoryRow.typeLabel(type), type == selected));
		}
		return options;
	}

	record FilterOption(String value, String label, boolean selected) {
	}

	// 실패 분석 추이·증감 부분 갱신(#1746): 기간 버튼이 이 fragment를 htmx로 다시 불러 차트·증감·대체표를 갈아끼운다.
	@HxRequest
	@GetMapping("/admin/notifications/push/trends")
	String pushNotificationTrends(
		@RequestParam(name = "days", defaultValue = "7") int days,
		Model model
	) {
		populateTrends(days, model);
		return "admin/notifications/push :: trends";
	}

	private void populateTrends(int days, Model model) {
		AdminMetricChart chart = metricQueryService.chart(TREND_KEYS, days);
		model.addAttribute("trendChart", chart);
		model.addAttribute("trendJson", toJson(chart));
		model.addAttribute("trendDays", chart.days());
		model.addAttribute("exportKeys", TREND_KEYS);
		model.addAttribute("comparisons", metricQueryService.compare(TREND_KEYS, days)
			.stream()
			.map(comparison -> AnalyticsComparisonCard.from(comparison, HIGHER_IS_BETTER.contains(comparison.key())))
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
}
