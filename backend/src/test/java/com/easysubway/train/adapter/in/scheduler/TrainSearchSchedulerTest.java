package com.easysubway.train.adapter.in.scheduler;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.easysubway.train.application.TrainSearchService;
import com.easysubway.train.application.TrainSearchService.TrainSearchFailure;
import java.lang.reflect.Method;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

class TrainSearchSchedulerTest {

	@Test
	void refreshesCatalogAndPurgesExpiredCache() {
		TrainSearchService service = mock(TrainSearchService.class);
		TrainSearchScheduler scheduler = new TrainSearchScheduler(service);

		scheduler.refreshCatalog();
		scheduler.purgeExpiredCache();

		verify(service).refreshCatalog();
		verify(service).purgeExpired();
	}

	@Test
	void providerFailureDoesNotStopFutureScheduledRuns() {
		TrainSearchService service = mock(TrainSearchService.class);
		doThrow(new TrainSearchFailure("TRAIN_SEARCH_UNAVAILABLE")).when(service).refreshCatalog();
		TrainSearchScheduler scheduler = new TrainSearchScheduler(service);

		assertThatCode(scheduler::refreshCatalog).doesNotThrowAnyException();
	}

	@Test
	void catalogRefreshUsesDedicatedTaskScheduler() throws Exception {
		Method refresh = TrainSearchScheduler.class.getDeclaredMethod("refreshCatalog");
		assertThatCode(() -> {
			String scheduler = refresh.getAnnotation(Scheduled.class).scheduler();
			if (!"trainSearchTaskScheduler".equals(scheduler)) {
				throw new AssertionError("unexpected scheduler: " + scheduler);
			}
		}).doesNotThrowAnyException();

		try (var context = new AnnotationConfigApplicationContext(TrainSearchSchedulingConfiguration.class)) {
			assertThatCode(() -> context.getBean("trainSearchTaskScheduler", ThreadPoolTaskScheduler.class))
				.doesNotThrowAnyException();
		}
	}
}
