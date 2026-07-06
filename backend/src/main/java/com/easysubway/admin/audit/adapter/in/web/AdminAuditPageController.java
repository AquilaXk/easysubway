package com.easysubway.admin.audit.adapter.in.web;

import com.easysubway.admin.audit.application.AdminAuditQuery;
import com.easysubway.admin.audit.application.port.out.AdminAuditEventRepository;
import com.easysubway.admin.audit.domain.AdminAuditEvent;
import com.easysubway.admin.audit.domain.AdminAuditEventType;
import com.easysubway.admin.audit.domain.AdminAuditOutcome;
import com.easysubway.common.web.pagination.EgovPaginationView;
import io.github.wimdeblauwe.htmx.spring.boot.mvc.HxRequest;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;

/**
 * 관리자 감사·개인정보 조회 로그 표준 테이블(#1747). 유형·actor·결과·기간·target 검색·"사유 없는 조회"
 * 필터를 서버 질의로 적용하고, htmx로 결과 fragment만 부분 갱신한다(no-JS는 폼 제출로 풀페이지 동작).
 *
 * <p>두 프로그램(관리자 감사·개인정보 조회 로그)이 같은 템플릿을 공유하되, 개인정보 화면은
 * {@code PRIVACY_READ}로 유형을 강제해 권한 분리를 URL이 아니라 질의로도 보장한다.
 */
@Controller
class AdminAuditPageController {

	private static final String AUDITS_PATH = "/admin/audits/page";
	private static final String PRIVACY_PATH = "/admin/audits/privacy/page";
	private static final String AUDITS_BASE = "/admin/audits";
	private static final String PRIVACY_BASE = "/admin/audits/privacy";

	private final AdminAuditEventRepository auditEventRepository;

	AdminAuditPageController(AdminAuditEventRepository auditEventRepository) {
		this.auditEventRepository = auditEventRepository;
	}

	@GetMapping(AUDITS_PATH)
	@PreAuthorize("hasAuthority('admin.audit.read')")
	String auditPage(AuditFilterParams params, Model model) {
		populateAuditModel(model, auditContext(), params);
		return "admin/audits/list";
	}

	// 결과 부분 갱신(#1747): 필터·페이지 링크가 이 fragment를 htmx로 다시 불러 표·페이지네이션만 갈아끼운다.
	// htmx 히스토리 복원 요청은 셸을 포함한 풀페이지를 돌려줘 화면이 깨지지 않게 한다.
	@HxRequest
	@GetMapping(AUDITS_PATH)
	@PreAuthorize("hasAuthority('admin.audit.read')")
	String auditFragment(
		AuditFilterParams params,
		@RequestHeader(value = "HX-History-Restore-Request", required = false) boolean historyRestore,
		Model model
	) {
		populateAuditModel(model, auditContext(), params);
		return historyRestore ? "admin/audits/list" : "admin/audits/list :: auditResults";
	}

	@GetMapping(PRIVACY_PATH)
	@PreAuthorize("hasAuthority('admin.privacy-log.read')")
	String privacyAuditPage(AuditFilterParams params, Model model) {
		populateAuditModel(model, privacyContext(), params);
		return "admin/audits/list";
	}

	@HxRequest
	@GetMapping(PRIVACY_PATH)
	@PreAuthorize("hasAuthority('admin.privacy-log.read')")
	String privacyAuditFragment(
		AuditFilterParams params,
		@RequestHeader(value = "HX-History-Restore-Request", required = false) boolean historyRestore,
		Model model
	) {
		populateAuditModel(model, privacyContext(), params);
		return historyRestore ? "admin/audits/list" : "admin/audits/list :: auditResults";
	}

	private static ScreenContext auditContext() {
		return new ScreenContext("관리자 감사", "a-audits", AUDITS_PATH, AUDITS_BASE, null, false);
	}

	private static ScreenContext privacyContext() {
		return new ScreenContext(
			"개인정보 조회 로그", "a-privacy-audits", PRIVACY_PATH, PRIVACY_BASE,
			AdminAuditEventType.PRIVACY_READ, true);
	}

	private void populateAuditModel(Model model, ScreenContext context, AuditFilterParams params) {
		AdminAuditQuery query = AdminAuditQuery.of(
			context.forcedEventType(),
			params.eventTypeOrNull(),
			params.actor(),
			params.outcomeOrNull(),
			params.keyword(),
			params.from(),
			params.to(),
			params.reasonMissing(),
			params.page(),
			params.size()
		);

		long total = auditEventRepository.count(query);
		EgovPaginationView pageView = EgovPaginationView.from(query.page(), query.size(), total);
		AdminAuditQuery pageQuery = query.withPage(pageView.page());
		List<AuditEventRow> events = auditEventRepository.search(pageQuery).stream()
			.map(AuditEventRow::from)
			.toList();

		model.addAttribute("title", context.title());
		model.addAttribute("paginationLabel", context.title() + " 페이지");
		model.addAttribute("activeProgram", context.activeProgram());
		model.addAttribute("basePath", context.path());
		model.addAttribute("detailBase", context.detailBase());
		model.addAttribute("exportPath", context.detailBase() + "/export");
		model.addAttribute("privacyMode", context.privacyMode());
		model.addAttribute("events", events);
		model.addAttribute("total", total);
		model.addAttribute("page", pageView);
		model.addAttribute("paginationLinks", pageView.links(context.path(), filterParams(pageQuery)));

		// 필터 툴바 상태·옵션.
		model.addAttribute("selectedEventType", pageQuery.eventType());
		model.addAttribute("selectedActor", pageQuery.actor());
		model.addAttribute("selectedOutcome", pageQuery.outcome());
		model.addAttribute("keyword", pageQuery.targetKeyword());
		model.addAttribute("from", pageQuery.occurredFrom());
		model.addAttribute("to", pageQuery.occurredTo());
		model.addAttribute("reasonMissing", pageQuery.reasonMissing());
		model.addAttribute("eventTypeOptions", eventTypeOptions(pageQuery.eventType()));
		model.addAttribute("outcomeOptions", outcomeOptions(pageQuery.outcome()));
		model.addAttribute("actorOptions", actorOptions(context.forcedEventType(), pageQuery.actor()));
	}

	// 페이지네이션·필터 링크가 현재 필터를 유지하도록 활성 파라미터만 전달한다(널·빈·거짓 값 생략).
	private static Map<String, Object> filterParams(AdminAuditQuery query) {
		Map<String, Object> params = new LinkedHashMap<>();
		params.put("eventType", query.eventType() == null ? null : query.eventType().name());
		params.put("actor", query.actor());
		params.put("outcome", query.outcome() == null ? null : query.outcome().name());
		params.put("keyword", query.targetKeyword());
		params.put("from", query.occurredFrom());
		params.put("to", query.occurredTo());
		if (query.reasonMissing()) {
			params.put("reasonMissing", "true");
		}
		return params;
	}

	private List<FilterOption> actorOptions(AdminAuditEventType scopeEventType, String selected) {
		List<FilterOption> options = new ArrayList<>();
		options.add(new FilterOption("", "actor 전체", selected == null));
		for (String actor : auditEventRepository.findDistinctActors(scopeEventType)) {
			options.add(new FilterOption(actor, actor, actor.equals(selected)));
		}
		return options;
	}

	private static List<FilterOption> eventTypeOptions(AdminAuditEventType selected) {
		List<FilterOption> options = new ArrayList<>();
		options.add(new FilterOption("", "유형 전체", selected == null));
		for (AdminAuditEventType type : AdminAuditEventType.values()) {
			options.add(new FilterOption(type.name(), AuditLabels.eventType(type), type == selected));
		}
		return options;
	}

	private static List<FilterOption> outcomeOptions(AdminAuditOutcome selected) {
		List<FilterOption> options = new ArrayList<>();
		options.add(new FilterOption("", "결과 전체", selected == null));
		for (AdminAuditOutcome outcome : AdminAuditOutcome.values()) {
			options.add(new FilterOption(outcome.name(), AuditLabels.outcome(outcome), outcome == selected));
		}
		return options;
	}

	record FilterOption(String value, String label, boolean selected) {
	}

	private record ScreenContext(
		String title,
		String activeProgram,
		String path,
		String detailBase,
		AdminAuditEventType forcedEventType,
		boolean privacyMode
	) {
	}

	/**
	 * 감사 필터 폼 바인딩. 빈 문자열이 enum 변환 400을 내지 않도록 String으로 받아 파싱한다
	 * (Spring StringToEnum이 빈 문자열도 변환 시도하는 것과 무관하게 안전).
	 */
	record AuditFilterParams(
		String eventType,
		String actor,
		String outcome,
		String keyword,
		@DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
		@DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
		Boolean reasonMissing,
		Integer page,
		Integer size
	) {

		AdminAuditEventType eventTypeOrNull() {
			return parseEnum(eventType, AdminAuditEventType.class);
		}

		AdminAuditOutcome outcomeOrNull() {
			return parseEnum(outcome, AdminAuditOutcome.class);
		}

		private static <E extends Enum<E>> E parseEnum(String value, Class<E> type) {
			if (value == null || value.isBlank()) {
				return null;
			}
			try {
				return Enum.valueOf(type, value.trim());
			} catch (IllegalArgumentException exception) {
				return null;
			}
		}
	}

	record AuditEventRow(
		Long id,
		String eventType,
		String eventTypeLabel,
		String actor,
		String rolePermission,
		String requestId,
		String clientIp,
		String userAgent,
		String targetType,
		String targetId,
		String action,
		String outcome,
		String outcomeLabel,
		String outcomeTone,
		String reason,
		String occurredAt
	) {

		static AuditEventRow from(AdminAuditEvent event) {
			return new AuditEventRow(
				event.id(),
				event.eventType().name(),
				AuditLabels.eventType(event.eventType()),
				event.actor(),
				orDash(event.rolePermission()),
				orDash(event.requestId()),
				orDash(event.clientIp()),
				orDash(event.userAgent()),
				event.targetType(),
				orDash(event.targetId()),
				event.action(),
				event.outcome().name(),
				AuditLabels.outcome(event.outcome()),
				event.outcome() == AdminAuditOutcome.FAILURE ? "failure" : "success",
				orDash(event.reason()),
				event.occurredAt().toString()
			);
		}

		private static String orDash(String value) {
			return value == null || value.isBlank() ? "-" : value;
		}
	}
}
