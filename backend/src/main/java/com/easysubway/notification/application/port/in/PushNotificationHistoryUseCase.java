package com.easysubway.notification.application.port.in;

import com.easysubway.common.domain.PageResult;
import com.easysubway.notification.domain.PushNotification;

/**
 * 관리자 푸시 발송 이력 조회(#1746). 필터·페이지네이션이 적용된 이력과 총 건수를 준다.
 */
public interface PushNotificationHistoryUseCase {

	PageResult<PushNotification> searchPushNotifications(PushNotificationHistoryQuery query);

	long countPushNotifications(PushNotificationHistoryQuery query);
}
