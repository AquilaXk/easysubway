package com.easysubway.collection.adapter.out.batch;

import com.easysubway.collection.application.service.DataCollectionRunRecorder;
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
	static final String STEP_NAME = "recordTransitMasterCollectionStep";

	@Bean
	Job transitMasterCollectionJob(JobRepository jobRepository, Step recordTransitMasterCollectionStep) {
		return new JobBuilder(JOB_NAME, jobRepository)
			.start(recordTransitMasterCollectionStep)
			.build();
	}

	@Bean
	Step recordTransitMasterCollectionStep(
		JobRepository jobRepository,
		PlatformTransactionManager transactionManager,
		DataCollectionRunRecorder dataCollectionRunRecorder
	) {
		return new StepBuilder(STEP_NAME, jobRepository)
			.tasklet((contribution, chunkContext) -> {
				String runId = (String) chunkContext.getStepContext()
					.getJobParameters()
					.getOrDefault("runId", "collection-" + UUID.randomUUID());
				String requestedBy = (String) chunkContext.getStepContext()
					.getJobParameters()
					.getOrDefault("requestedBy", JOB_NAME);
				dataCollectionRunRecorder.recordTransitMasterRun(runId, requestedBy);
				return RepeatStatus.FINISHED;
			}, transactionManager)
			.build();
	}
}
