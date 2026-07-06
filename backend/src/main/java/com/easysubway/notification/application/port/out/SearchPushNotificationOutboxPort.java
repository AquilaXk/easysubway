package com.easysubway.notification.application.port.out;

import com.easysubway.notification.application.port.in.PushNotificationHistoryQuery;
import com.easysubway.notification.domain.PushNotification;
import java.util.List;

/**
 * 관리자 발송 이력 콘솔(#1746)의 outbox 조회 포트.
 *
 * <p>필터·페이지네이션이 적용된 이력 목록과 그 총 건수를 준다. 목록과 건수가 같은 질의를 공유해
 * 페이지네이션·정합을 보장한다.
 */
public interface SearchPushNotificationOutboxPort {

	List<PushNotification> searchPushNotifications(PushNotificationHistoryQuery query);

	long countPushNotifications(PushNotificationHistoryQuery query);
}
