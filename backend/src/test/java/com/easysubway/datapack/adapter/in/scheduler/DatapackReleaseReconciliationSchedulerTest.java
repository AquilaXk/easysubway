package com.easysubway.datapack.adapter.in.scheduler;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import com.easysubway.datapack.application.service.DatapackReleaseReconciliationService;
import org.junit.jupiter.api.Test;

class DatapackReleaseReconciliationSchedulerTest {
	@Test
	void delegatesToReconciler() {
		var service = mock(DatapackReleaseReconciliationService.class);
		new DatapackReleaseReconciliationScheduler(service).run();
		verify(service).reconcileDue();
	}
}
