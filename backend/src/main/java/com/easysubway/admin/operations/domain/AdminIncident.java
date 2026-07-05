package com.easysubway.admin.operations.domain;

import java.time.LocalDateTime;

public record AdminIncident(
	String incidentId,
	String severity,
	AdminIncidentStatus status,
	String source,
	String summary,
	String owner,
	LocalDateTime openedAt,
	LocalDateTime resolvedAt,
	String resolution
) {

	public AdminIncident {
		incidentId = clean(incidentId, "incident id가 필요합니다.");
		severity = clean(severity, "incident severity가 필요합니다.");
		source = clean(source, "incident source가 필요합니다.");
		summary = clean(summary, "incident summary가 필요합니다.");
		owner = clean(owner, "incident owner가 필요합니다.");
		resolution = cleanNullable(resolution);
		if (status == null) {
			throw new IllegalArgumentException("incident status가 필요합니다.");
		}
		if (openedAt == null) {
			throw new IllegalArgumentException("incident openedAt이 필요합니다.");
		}
		if (status.isResolved() && (resolvedAt == null || resolution == null)) {
			throw new IllegalArgumentException("해결된 incident는 resolvedAt과 resolution이 필요합니다.");
		}
		if (!status.isResolved() && (resolvedAt != null || resolution != null)) {
			throw new IllegalArgumentException("열린 incident는 resolvedAt과 resolution을 가질 수 없습니다.");
		}
	}

	/**
	 * 대상 상태로 전이한 새 incident를 만든다. 전이 규칙은 {@link AdminIncidentStatus}가 강제한다.
	 * 종결로 전이할 때만 resolution/resolvedAt을 채우고, 그 외 전이는 두 필드를 비운다.
	 */
	public AdminIncident transitionTo(AdminIncidentStatus target, LocalDateTime at, String resolution) {
		if (!status.canTransitionTo(target)) {
			throw new IllegalStateException("%s에서 %s로 전이할 수 없습니다.".formatted(status, target));
		}
		if (at == null) {
			throw new IllegalArgumentException("전이 시각이 필요합니다.");
		}
		if (target.isResolved()) {
			return new AdminIncident(incidentId, severity, target, source, summary, owner, openedAt, at, resolution);
		}
		return new AdminIncident(incidentId, severity, target, source, summary, owner, openedAt, null, null);
	}

	private static String clean(String value, String message) {
		if (value == null || value.isBlank()) {
			throw new IllegalArgumentException(message);
		}
		return value.trim();
	}

	private static String cleanNullable(String value) {
		return value == null || value.isBlank() ? null : value.trim();
	}
}
