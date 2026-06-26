package com.easysubway.admin.identity.domain;

import java.time.LocalDateTime;

public record AdminLoginAudit(
	String loginId,
	AdminIdentityAuthMethod authMethod,
	String outcome,
	String reason,
	LocalDateTime occurredAt
) {
}
