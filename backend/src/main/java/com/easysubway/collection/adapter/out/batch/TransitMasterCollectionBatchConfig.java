package com.easysubway.collection.adapter.out.batch;

import com.easysubway.collection.application.service.DataCollectionRunRecorder;
import com.easysubway.collection.domain.InvalidDataCollectionException;
import java.util.UUID;
import org.springframework.batch.core.Job;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.repeat.RepeatStatus;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration
class TransitMasterCollectionBatchConfig {

	static final String JOB_NAME = "transitMasterCollectionJob";
	static final String FETCH_STEP_NAME = "fetchTransitMasterCollectionStep";
	static final String ARCHIVE_STEP_NAME = "archiveTransitMasterCollectionStep";
	static final String VALIDATE_STEP_NAME = "validateTransitMasterCollectionStep";
	static final String PARSE_STEP_NAME = "parseTransitMasterCollectionStep";
	static final String DIFF_STEP_NAME = "diffTransitMasterCollectionStep";
	static final String STAGE_STEP_NAME = "stageTransitMasterCollectionStep";

	@Bean
	Job transitMasterCollectionJob(
		JobRepository jobRepository,
		Step fetchTransitMasterCollectionStep,
		Step archiveTransitMasterCollectionStep,
		Step validateTransitMasterCollectionStep,
		Step parseTransitMasterCollectionStep,
		Step diffTransitMasterCollectionStep,
		Step stageTransitMasterCollectionStep
	) {
		return new JobBuilder(JOB_NAME, jobRepository)
			.start(fetchTransitMasterCollectionStep)
			.next(archiveTransitMasterCollectionStep)
			.next(validateTransitMasterCollectionStep)
			.next(parseTransitMasterCollectionStep)
			.next(diffTransitMasterCollectionStep)
			.next(stageTransitMasterCollectionStep)
			.build();
	}

	@Bean
	Step fetchTransitMasterCollectionStep(
		JobRepository jobRepository,
		PlatformTransactionManager transactionManager
	) {
		return markerStep(FETCH_STEP_NAME, jobRepository, transactionManager);
	}

	@Bean
	Step archiveTransitMasterCollectionStep(
		JobRepository jobRepository,
		PlatformTransactionManager transactionManager
	) {
		return markerStep(ARCHIVE_STEP_NAME, jobRepository, transactionManager);
	}

	@Bean
	Step validateTransitMasterCollectionStep(
		JobRepository jobRepository,
		PlatformTransactionManager transactionManager
	) {
		return markerStep(VALIDATE_STEP_NAME, jobRepository, transactionManager);
	}

	@Bean
	Step parseTransitMasterCollectionStep(
		JobRepository jobRepository,
		PlatformTransactionManager transactionManager
	) {
		return markerStep(PARSE_STEP_NAME, jobRepository, transactionManager);
	}

	@Bean
	Step diffTransitMasterCollectionStep(
		JobRepository jobRepository,
		PlatformTransactionManager transactionManager
	) {
		return markerStep(DIFF_STEP_NAME, jobRepository, transactionManager);
	}

	@Bean
	Step stageTransitMasterCollectionStep(
		JobRepository jobRepository,
		PlatformTransactionManager transactionManager,
		DataCollectionRunRecorder dataCollectionRunRecorder
	) {
		return new StepBuilder(STAGE_STEP_NAME, jobRepository)
			.tasklet((contribution, chunkContext) -> {
				String runId = (String) chunkContext.getStepContext()
					.getJobParameters()
					.getOrDefault("runId", "collection-" + UUID.randomUUID());
				Object requestedByParameter = chunkContext.getStepContext()
					.getJobParameters()
					.get("requestedBy");
				if (!(requestedByParameter instanceof String requestedBy) || requestedBy.isBlank()) {
					throw new InvalidDataCollectionException("요청자 식별자가 필요합니다.");
				}
				dataCollectionRunRecorder.recordTransitMasterRun(runId, requestedBy);
				return RepeatStatus.FINISHED;
			}, transactionManager)
			.build();
	}

	private static Step markerStep(
		String stepName,
		JobRepository jobRepository,
		PlatformTransactionManager transactionManager
	) {
		return new StepBuilder(stepName, jobRepository)
			.tasklet((contribution, chunkContext) -> RepeatStatus.FINISHED, transactionManager)
			.build();
	}
}
