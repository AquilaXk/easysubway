package com.easysubway.admin.audit.application.port.out;

import com.easysubway.admin.audit.application.AdminAuditQuery;
import com.easysubway.admin.audit.domain.AdminAuditEvent;
import com.easysubway.admin.audit.domain.AdminAuditEventType;
import java.util.List;

public interface AdminAuditEventRepository {

	void save(AdminAuditEvent event);

	List<AdminAuditEvent> findRecent(AdminAuditEventType eventType, int limit);

	default List<AdminAuditEvent> findRecent(AdminAuditEventType eventType, int limit, int offset) {
		return offset <= 0 ? findRecent(eventType, limit) : List.of();
	}

	/** 필터·페이지네이션이 적용된 감사 이벤트 목록(#1747). 발생 최신순. */
	List<AdminAuditEvent> search(AdminAuditQuery query);

	/** 같은 필터의 총 건수. 목록과 같은 질의를 공유해 페이지네이션·내보내기 정합을 보장한다. */
	long count(AdminAuditQuery query);

	/**
	 * actor 필터 select 옵션용. scopeEventType이 지정되면(개인정보 로그) 그 유형 이벤트의 actor만 준다.
	 * 정렬된 distinct 목록.
	 */
	List<String> findDistinctActors(AdminAuditEventType scopeEventType);
}
