package com.easysubway.collection.application.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.easysubway.collection.adapter.out.persistence.InMemoryDataCollectionRunRepository;
import com.easysubway.collection.application.port.in.RunDataCollectionCommand;
import com.easysubway.collection.domain.DataCollectionSource;
import com.easysubway.collection.domain.DataCollectionStatus;
import com.easysubway.collection.domain.InvalidDataCollectionException;
import com.easysubway.transit.adapter.out.persistence.InMemoryTransitMasterRepository;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("데이터 수집 실행 기록 작성기")
class DataCollectionRunRecorderTest {

	private static final Clock CLOCK = Clock.fixed(
		Instant.parse("2026-06-14T02:00:00Z"),
		ZoneId.of("Asia/Seoul")
	);

	private final InMemoryDataCollectionRunRepository repository = new InMemoryDataCollectionRunRepository();
	private final DataCollectionRunRecorder recorder = new DataCollectionRunRecorder(
		new InMemoryTransitMasterRepository(),
		repository,
		CLOCK
	);

	@Test
	@DisplayName("도시철도 마스터 데이터 수집 실행 기록을 완료 상태로 남긴다")
	void recordTransitMasterRunStoresCompletedRun() {
		var run = recorder.recordTransitMasterRun("collection-test", "admin-user");

		assertThat(run.runId()).isEqualTo("collection-test");
		assertThat(run.source()).isEqualTo(DataCollectionSource.TRANSIT_MASTER);
		assertThat(run.status()).isEqualTo(DataCollectionStatus.COMPLETED);
		assertThat(run.requestedBy()).isEqualTo("admin-user");
		assertThat(run.startedAt()).isEqualTo(LocalDateTime.of(2026, 6, 14, 11, 0));
		assertThat(run.completedAt()).isEqualTo(LocalDateTime.of(2026, 6, 14, 11, 0));
		assertThat(run.collectedCount()).isEqualTo(13);
		assertThat(repository.loadRun("collection-test")).contains(run);
	}

	@Test
	@DisplayName("최근 실행 기록은 최신 실행부터 제한 개수만 조회한다")
	void listRecentRunsReturnsLatestRunsFirst() {
		recorder.recordTransitMasterRun("collection-a", "admin-a");
		recorder.recordTransitMasterRun("collection-b", "admin-b");

		var recentRuns = repository.loadRecentRuns(1);

		assertThat(recentRuns)
			.extracting("requestedBy")
			.containsExactly("admin-b");
	}

	@Test
	@DisplayName("배치 실행 명령은 수집 대상과 요청자를 요구한다")
	void runCommandRequiresSourceAndRequester() {
		assertThatThrownBy(() -> new RunDataCollectionCommand(null, "admin-user"))
			.isInstanceOf(InvalidDataCollectionException.class)
			.hasMessage("수집 대상을 선택해야 합니다.");

		assertThatThrownBy(() -> new RunDataCollectionCommand(DataCollectionSource.TRANSIT_MASTER, ""))
			.isInstanceOf(InvalidDataCollectionException.class)
			.hasMessage("요청자 식별자가 필요합니다.");
	}
}
