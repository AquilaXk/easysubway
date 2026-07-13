package com.easysubway.realtime.adapter.in.scheduler;

import com.easysubway.realtime.application.port.out.RealtimeArrivalArchivePort;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.Instant;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@Profile("prod | staging | release | prod-like")
public class RealtimeArrivalArchiveRetentionScheduler {
	private static final Logger log = LoggerFactory.getLogger(RealtimeArrivalArchiveRetentionScheduler.class);

	private final RealtimeArrivalArchivePort archivePort;
	private final Counter purgeFailureCounter;

	public RealtimeArrivalArchiveRetentionScheduler(
		RealtimeArrivalArchivePort archivePort,
		MeterRegistry meterRegistry
	) {
		this.archivePort = archivePort;
		this.purgeFailureCounter = Counter.builder("easysubway.realtime.archive.purge.failures")
			.tag("provider", "seoul-topis")
			.tag("operation", "delete-expired")
			.register(meterRegistry);
	}

	@Scheduled(
		cron = "${easysubway.realtime.archive.purge.cron:0 20 3 * * *}",
		zone = "UTC"
	)
	void purgeExpiredObservations() {
		try {
			int deleted = archivePort.deleteExpired(Instant.now());
			log.info("Realtime arrival archive retention purge completed. deletedRows={}", deleted);
		} catch (RuntimeException exception) {
			purgeFailureCounter.increment();
			log.error(
				"Realtime arrival archive retention purge failed. providerId={} operation={} exceptionType={}",
				"seoul-topis",
				"delete-expired",
				exception.getClass().getSimpleName(),
				exception
			);
		}
	}
}
