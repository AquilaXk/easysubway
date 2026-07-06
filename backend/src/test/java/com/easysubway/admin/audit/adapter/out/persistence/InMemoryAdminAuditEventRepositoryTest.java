package com.easysubway.admin.audit.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.admin.audit.application.AdminAuditQuery;
import com.easysubway.admin.audit.domain.AdminAuditEvent;
import com.easysubway.admin.audit.domain.AdminAuditEventType;
import com.easysubway.admin.audit.domain.AdminAuditOutcome;
import java.time.LocalDateTime;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("인메모리 관리자 감사 이벤트 저장소")
class InMemoryAdminAuditEventRepositoryTest {

	private final InMemoryAdminAuditEventRepository repository = new InMemoryAdminAuditEventRepository();

	@Test
	@DisplayName("감사 검색은 유형·actor·결과·target·사유없음으로 필터하고 발생 최신순으로 정렬한다")
	void searchFiltersAuditEvents() {
		LocalDateTime base = LocalDateTime.of(2026, 6, 27, 9, 0);
		repository.save(event(AdminAuditEventType.ADMIN_ACTION, "admin-a", AdminAuditOutcome.SUCCESS,
			"REPORT", "report-1", "업무 맥락", base));
		repository.save(event(AdminAuditEventType.PRIVACY_READ, "admin-b", AdminAuditOutcome.SUCCESS,
			"REPORT", "report-2", null, base.plusMinutes(1)));
		repository.save(event(AdminAuditEventType.ADMIN_ACTION, "admin-a", AdminAuditOutcome.FAILURE,
			"INCIDENT", "incident-9", "업무 맥락", base.plusMinutes(2)));

		assertThat(repository.search(query(AdminAuditEventType.ADMIN_ACTION, "admin-a", null, null, false)))
			.extracting(AdminAuditEvent::targetId).containsExactly("incident-9", "report-1");
		assertThat(repository.search(query(null, null, AdminAuditOutcome.FAILURE, null, false)))
			.extracting(AdminAuditEvent::targetId).containsExactly("incident-9");
		assertThat(repository.search(query(null, null, null, "report", false)))
			.extracting(AdminAuditEvent::targetId).containsExactly("report-2", "report-1");
		assertThat(repository.search(query(null, null, null, null, true)))
			.extracting(AdminAuditEvent::targetId).containsExactly("report-2");
		assertThat(repository.count(query(AdminAuditEventType.ADMIN_ACTION, null, null, null, false))).isEqualTo(2);
		assertThat(repository.findDistinctActors(null)).containsExactly("admin-a", "admin-b");
		assertThat(repository.findDistinctActors(AdminAuditEventType.PRIVACY_READ)).containsExactly("admin-b");
	}

	@Test
	@DisplayName("감사 검색은 페이지 크기·오프셋으로 잘라낸다")
	void searchPaginates() {
		LocalDateTime base = LocalDateTime.of(2026, 6, 27, 9, 0);
		for (int index = 0; index < 5; index++) {
			repository.save(event(AdminAuditEventType.ADMIN_ACTION, "admin-a", AdminAuditOutcome.SUCCESS,
				"REPORT", "report-" + index, "업무 맥락", base.plusMinutes(index)));
		}

		assertThat(repository.search(new AdminAuditQuery(null, null, null, null, null, null, false, 0, 2)))
			.extracting(AdminAuditEvent::targetId).containsExactly("report-4", "report-3");
		assertThat(repository.search(new AdminAuditQuery(null, null, null, null, null, null, false, 2, 2)))
			.extracting(AdminAuditEvent::targetId).containsExactly("report-0");
	}

	private static AdminAuditQuery query(
		AdminAuditEventType eventType,
		String actor,
		AdminAuditOutcome outcome,
		String targetKeyword,
		boolean reasonMissing
	) {
		return AdminAuditQuery.of(
			null, eventType, actor, outcome, targetKeyword, null, null, reasonMissing, null, null);
	}

	private AdminAuditEvent event(
		AdminAuditEventType type,
		String actor,
		AdminAuditOutcome outcome,
		String targetType,
		String targetId,
		String reason,
		LocalDateTime occurredAt
	) {
		return new AdminAuditEvent(
			null, type, actor, "admin.view", "request-1", "127.0.0.1", "JUnit",
			targetType, targetId, "ACTION", outcome, reason, occurredAt);
	}
}
