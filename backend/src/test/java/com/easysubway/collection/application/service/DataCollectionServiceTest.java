package com.easysubway.collection.application.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import com.easysubway.collection.adapter.out.persistence.InMemoryDataCollectionRunRepository;
import com.easysubway.collection.application.port.in.RunDataCollectionCommand;
import com.easysubway.collection.domain.DataCollectionRun;
import com.easysubway.collection.domain.DataCollectionSource;
import com.easysubway.collection.domain.DataCollectionStatus;
import com.easysubway.collection.domain.InvalidDataCollectionException;
import java.time.LocalDateTime;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.batch.core.Job;
import org.springframework.batch.core.JobExecution;
import org.springframework.batch.core.JobParametersInvalidException;
import org.springframework.batch.core.launch.JobLauncher;

@DisplayName("데이터 수집 서비스")
class DataCollectionServiceTest {

	@Test
	@DisplayName("같은 source 실행이 RUNNING이면 새 배치를 launch하지 않는다")
	void runningSourceRejectsSecondLaunch() {
		var repository = new InMemoryDataCollectionRunRepository();
		repository.saveRun(runningRun("collection-running"));
		var launchCount = new AtomicInteger();
		JobLauncher launcher = (job, parameters) -> {
			launchCount.incrementAndGet();
			return mock(JobExecution.class);
		};
		var service = new DataCollectionService(
			repository,
			repository,
			() -> "collection-next",
			launcher,
			mock(Job.class)
		);

		assertThatThrownBy(() -> service.runCollection(
			new RunDataCollectionCommand(DataCollectionSource.TRANSIT_MASTER, "admin-user")
		))
			.isInstanceOf(InvalidDataCollectionException.class)
			.hasMessage("같은 수집 대상이 이미 실행 중입니다.");
		assertThat(launchCount).hasValue(0);
	}

	@Test
	@DisplayName("배치 launch 실패는 사전 저장한 같은 실행을 FAILED로 갱신한다")
	void launchFailureMarksClaimedRunAsFailed() {
		var repository = new InMemoryDataCollectionRunRepository();
		JobLauncher launcher = (job, parameters) -> {
			throw new JobParametersInvalidException("launch down");
		};
		var service = new DataCollectionService(
			repository,
			repository,
			() -> "collection-failed",
			launcher,
			mock(Job.class)
		);

		assertThatThrownBy(() -> service.runCollection(
			new RunDataCollectionCommand(DataCollectionSource.TRANSIT_MASTER, "admin-user")
		))
			.isInstanceOf(InvalidDataCollectionException.class)
			.hasMessage("데이터 수집 배치를 실행하지 못했습니다.");

		assertThat(repository.loadRun("collection-failed")).get()
			.extracting(DataCollectionRun::status, DataCollectionRun::failureMessage)
			.containsExactly(DataCollectionStatus.FAILED, "launch down");
	}

	private static DataCollectionRun runningRun(String runId) {
		return new DataCollectionRun(
			runId,
			DataCollectionSource.TRANSIT_MASTER,
			DataCollectionStatus.RUNNING,
			"admin-user",
			LocalDateTime.of(2026, 7, 18, 12, 0),
			null,
			0,
			null,
			false,
			"수집 실행 중입니다."
		);
	}
}
