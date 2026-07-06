package com.easysubway.notice.adapter.in.web;

import com.easysubway.notice.application.service.PublishNoticeCommand;
import com.easysubway.notice.domain.ServiceNoticeScope;
import com.easysubway.notice.domain.ServiceNoticeSeverity;
import java.time.LocalDateTime;

/**
 * 관리자 공지 발행 요청. scope/severity는 문자열로 받아 도메인 enum으로 변환한다.
 */
public record PublishNoticeRequest(
	String scope,
	String scopeValue,
	String title,
	String body,
	String severity,
	LocalDateTime expiresAt
) {

	public PublishNoticeCommand toCommand() {
		return new PublishNoticeCommand(
			ServiceNoticeScope.valueOf(scope),
			scopeValue,
			title,
			body,
			ServiceNoticeSeverity.valueOf(severity),
			expiresAt
		);
	}
}
