package com.easysubway.admin.audit.application;

import com.easysubway.admin.audit.domain.AdminAuditEventType;
import com.easysubway.admin.audit.domain.AdminAuditOutcome;
import java.time.LocalDate;

/**
 * 관리자 감사·개인정보 조회 로그 표준 테이블(#1747)의 서버 파라미터 질의.
 *
 * <p>이벤트 유형·actor·결과·발생 기간·target 검색과, 개인정보 로그 점검용 "사유 없는 조회" 필터,
 * 페이지네이션을 담는다. 개인정보 로그 화면은 {@code eventType}을 {@code PRIVACY_READ}로 고정해
 * 권한 분리(프로그램별 접근)를 URL이 아니라 질의로도 강제한다. 목록·건수·내보내기가 같은 질의를
 * 공유해 정합을 보장한다.
 */
public record AdminAuditQuery(
	AdminAuditEventType eventType,
	String actor,
	AdminAuditOutcome outcome,
	String targetKeyword,
	LocalDate occurredFrom,
	LocalDate occurredTo,
	boolean reasonMissing,
	int page,
	int size
) {

	public static final int DEFAULT_PAGE = 0;
	public static final int DEFAULT_SIZE = 20;
	public static final int MAX_SIZE = 100;

	public AdminAuditQuery {
		actor = blankToNull(actor);
		targetKeyword = blankToNull(targetKeyword);
		if (page < 0 || size <= 0) {
			throw new IllegalArgumentException("페이지 요청 값을 확인해야 합니다.");
		}
		size = Math.min(size, MAX_SIZE);
		if (page > Integer.MAX_VALUE / size) {
			throw new IllegalArgumentException("페이지 요청 값을 확인해야 합니다.");
		}
		if (occurredFrom != null && occurredTo != null && occurredFrom.isAfter(occurredTo)) {
			throw new IllegalArgumentException("발생 기간 시작이 종료보다 늦을 수 없습니다.");
		}
	}

	/**
	 * @param forcedEventType null이면 사용자가 고른 유형(nullable)을 쓰고, 지정되면 그 유형으로 고정한다
	 *                        (개인정보 로그 화면이 PRIVACY_READ로 강제).
	 */
	public static AdminAuditQuery of(
		AdminAuditEventType forcedEventType,
		AdminAuditEventType eventType,
		String actor,
		AdminAuditOutcome outcome,
		String targetKeyword,
		LocalDate occurredFrom,
		LocalDate occurredTo,
		Boolean reasonMissing,
		Integer page,
		Integer size
	) {
		return new AdminAuditQuery(
			forcedEventType != null ? forcedEventType : eventType,
			actor,
			outcome,
			targetKeyword,
			occurredFrom,
			occurredTo,
			Boolean.TRUE.equals(reasonMissing),
			page == null ? DEFAULT_PAGE : page,
			size == null ? DEFAULT_SIZE : size
		);
	}

	public AdminAuditQuery withPage(int nextPage) {
		return new AdminAuditQuery(
			eventType, actor, outcome, targetKeyword, occurredFrom, occurredTo, reasonMissing, nextPage, size);
	}

	public boolean hasEventType() {
		return eventType != null;
	}

	public boolean hasActor() {
		return actor != null;
	}

	public boolean hasOutcome() {
		return outcome != null;
	}

	public boolean hasTargetKeyword() {
		return targetKeyword != null;
	}

	public int offset() {
		return page * size;
	}

	private static String blankToNull(String value) {
		return (value == null || value.isBlank()) ? null : value.trim();
	}
}
