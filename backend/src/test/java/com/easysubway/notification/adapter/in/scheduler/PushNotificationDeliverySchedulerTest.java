package com.easysubway.notification.adapter.in.scheduler;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.notification.application.port.in.DeliverPushNotificationsCommand;
import com.easysubway.notification.application.port.in.PushNotificationDeliveryUseCase;
import com.easysubway.notification.application.port.out.LoadPendingPushNotificationOutboxPort;
import com.easysubway.notification.domain.PushNotification;
import com.easysubway.notification.domain.PushNotificationDeliveryResult;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

@DisplayName("푸시 알림 자동 발송 스케줄러")
class PushNotificationDeliverySchedulerTest {

	private PendingUserOutbox pendingUserOutbox;
	private RecordingDeliveryUseCase deliveryUseCase;
	private PushNotificationDeliveryScheduler scheduler;

	@BeforeEach
	void setUp() {
		pendingUserOutbox = new PendingUserOutbox();
		deliveryUseCase = new RecordingDeliveryUseCase();
		scheduler = new PushNotificationDeliveryScheduler(pendingUserOutbox, deliveryUseCase);
	}

	@Test
	@DisplayName("대기 중인 알림이 있는 사용자별로 발송 유스케이스를 호출한다")
	void deliverPendingNotificationsCallsDeliveryUseCaseForPendingUsers() {
		pendingUserOutbox.userIds = List.of("anonymous-user-1", "anonymous-user-2");

		scheduler.deliverPendingNotifications();

		assertThat(deliveryUseCase.deliveredUserIds)
			.containsExactly("anonymous-user-1", "anonymous-user-2");
	}

	@Test
	@DisplayName("한 사용자 발송이 실패해도 다음 사용자 처리를 계속한다")
	void deliverPendingNotificationsContinuesWhenOneUserFails() {
		pendingUserOutbox.userIds = List.of("anonymous-user-1", "anonymous-user-2");
		deliveryUseCase.failedUserId = "anonymous-user-1";

		scheduler.deliverPendingNotifications();

		assertThat(deliveryUseCase.deliveredUserIds)
			.containsExactly("anonymous-user-1", "anonymous-user-2");
	}

	@Test
	@DisplayName("자동 발송 스케줄러는 설정이 꺼져 있으면 빈을 등록하지 않는다")
	void schedulerBeanIsDisabledByDefault() {
		schedulerContextRunner()
			.run(context -> assertThat(context)
				.doesNotHaveBean(PushNotificationDeliveryScheduler.class));
	}

	@Test
	@DisplayName("자동 발송 스케줄러는 설정이 켜져 있으면 빈을 등록한다")
	void schedulerBeanIsEnabledWhenConfigured() {
		schedulerContextRunner()
			.withPropertyValues("easysubway.notifications.push.delivery.enabled=true")
			.run(context -> assertThat(context)
				.hasSingleBean(PushNotificationDeliveryScheduler.class));
	}

	private ApplicationContextRunner schedulerContextRunner() {
		return new ApplicationContextRunner()
			.withBean(LoadPendingPushNotificationOutboxPort.class, PendingUserOutbox::new)
			.withBean(PushNotificationDeliveryUseCase.class, RecordingDeliveryUseCase::new)
			.withUserConfiguration(PushNotificationDeliveryScheduler.class);
	}

	private static class PendingUserOutbox implements LoadPendingPushNotificationOutboxPort {

		private List<String> userIds = List.of();

		@Override
		public List<PushNotification> loadPendingPushNotifications(String userId) {
			return List.of();
		}

		@Override
		public List<String> loadPendingPushNotificationUserIds() {
			return userIds;
		}
	}

	private static class RecordingDeliveryUseCase implements PushNotificationDeliveryUseCase {

		private final List<String> deliveredUserIds = new ArrayList<>();
		private String failedUserId;

		@Override
		public PushNotificationDeliveryResult deliverPending(DeliverPushNotificationsCommand command) {
			deliveredUserIds.add(command.userId());
			if (command.userId().equals(failedUserId)) {
				throw new IllegalStateException("푸시 알림 발송 실패");
			}
			return new PushNotificationDeliveryResult(command.userId(), 0, 0, List.of());
		}
	}
}
