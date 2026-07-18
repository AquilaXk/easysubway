package com.easysubway.collection.application.service;

import com.easysubway.collection.application.port.in.DataCollectionUseCase;
import com.easysubway.collection.application.port.in.RunDataCollectionCommand;
import com.easysubway.collection.application.port.out.GenerateCollectionRunIdPort;
import com.easysubway.collection.application.port.out.LoadDataCollectionRunPort;
import com.easysubway.collection.application.port.out.SaveDataCollectionRunPort;
import com.easysubway.collection.domain.DataCollectionRun;
import com.easysubway.collection.domain.DataCollectionSource;
import com.easysubway.collection.domain.DataCollectionStatus;
import com.easysubway.collection.domain.InvalidDataCollectionException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.springframework.batch.core.BatchStatus;
import org.springframework.batch.core.Job;
import org.springframework.batch.core.JobExecution;
import org.springframework.batch.core.JobExecutionException;
import org.springframework.batch.core.JobParametersBuilder;
import org.springframework.batch.core.launch.JobLauncher;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

@Service
public class DataCollectionService implements DataCollectionUseCase {

	private final LoadDataCollectionRunPort loadDataCollectionRunPort;
	private final SaveDataCollectionRunPort saveDataCollectionRunPort;
	private final GenerateCollectionRunIdPort generateCollectionRunIdPort;
	private final JobLauncher jobLauncher;
	private final Job transitMasterCollectionJob;

	public DataCollectionService(
		LoadDataCollectionRunPort loadDataCollectionRunPort,
		SaveDataCollectionRunPort saveDataCollectionRunPort,
		GenerateCollectionRunIdPort generateCollectionRunIdPort,
		JobLauncher jobLauncher,
		@Qualifier("transitMasterCollectionJob") Job transitMasterCollectionJob
	) {
		this.loadDataCollectionRunPort = loadDataCollectionRunPort;
		this.saveDataCollectionRunPort = saveDataCollectionRunPort;
		this.generateCollectionRunIdPort = generateCollectionRunIdPort;
		this.jobLauncher = jobLauncher;
		this.transitMasterCollectionJob = transitMasterCollectionJob;
	}

	@Override
	public DataCollectionRun runCollection(RunDataCollectionCommand command) {
		return switch (command.source()) {
			case TRANSIT_MASTER -> launchTransitMasterCollection(command.requestedBy());
		};
	}

	@Override
	public List<DataCollectionRun> listRecentRuns(int limit) {
		return loadDataCollectionRunPort.loadRecentRuns(limit);
	}

	@Override
	public List<DataCollectionRun> listRecentRuns(int limit, int offset) {
		return loadDataCollectionRunPort.loadRecentRuns(limit, offset);
	}

	@Override
	public Optional<DataCollectionRun> getLatestCompletedRun(DataCollectionSource source) {
		return loadDataCollectionRunPort.loadLatestCompletedRun(source);
	}

	private DataCollectionRun launchTransitMasterCollection(String requestedBy) {
		String runId = generateCollectionRunIdPort.nextCollectionRunId();
		DataCollectionRun claimedRun = saveDataCollectionRunPort.saveRun(new DataCollectionRun(
			runId,
			DataCollectionSource.TRANSIT_MASTER,
			DataCollectionStatus.RUNNING,
			requestedBy,
			LocalDateTime.now(),
			null,
			0,
			null,
			false,
			"수집 실행 중입니다."
		));
		var parameters = new JobParametersBuilder()
			.addString("runId", runId)
			.addString("requestedBy", requestedBy)
			.addString("source", DataCollectionSource.TRANSIT_MASTER.name())
			.addLong("run.id", System.nanoTime())
			.toJobParameters();
		try {
			JobExecution execution = jobLauncher.run(transitMasterCollectionJob, parameters);
			if (execution.getStatus() != BatchStatus.COMPLETED) {
				Throwable failure = execution.getAllFailureExceptions().stream()
					.findFirst()
					.orElse(null);
				String failureMessage = DataCollectionFailureDetailSanitizer.operatorSafe(
					failure,
					execution.getStatus()
				);
				markFailed(claimedRun, failureMessage);
				throw new InvalidDataCollectionException("데이터 수집 배치를 실행하지 못했습니다.");
			}
		} catch (JobExecutionException exception) {
			markFailed(claimedRun, DataCollectionFailureDetailSanitizer.operatorSafe(exception));
			throw new InvalidDataCollectionException("데이터 수집 배치를 실행하지 못했습니다.", exception);
		}
		return loadDataCollectionRunPort.loadRun(runId)
			.orElseThrow(() -> new InvalidDataCollectionException("데이터 수집 실행 기록을 찾을 수 없습니다."));
	}

	private void markFailed(DataCollectionRun claimedRun, String failureMessage) {
		saveDataCollectionRunPort.saveRun(new DataCollectionRun(
			claimedRun.runId(),
			claimedRun.source(),
			DataCollectionStatus.FAILED,
			claimedRun.requestedBy(),
			claimedRun.startedAt(),
			LocalDateTime.now(),
			0,
			failureMessage,
			true,
			"일시 오류일 수 있습니다. 실패 사유를 확인한 뒤 같은 수집 대상을 다시 실행하세요."
		));
	}
}
