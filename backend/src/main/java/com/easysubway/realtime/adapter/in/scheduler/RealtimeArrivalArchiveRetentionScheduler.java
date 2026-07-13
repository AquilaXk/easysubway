package com.easysubway.realtime.adapter.in.scheduler;

import com.easysubway.realtime.application.port.out.RealtimeArrivalArchivePort;
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

	public RealtimeArrivalArchiveRetentionScheduler(RealtimeArrivalArchivePort archivePort) {
		this.archivePort = archivePort;
	}

	@Scheduled(
		cron = "${easysubway.realtime.archive.purge.cron:0 20 3 * * *}",
		zone = "UTC"
	)
	void purgeExpiredObservations() {
		int deleted = archivePort.deleteExpired(Instant.now());
		log.info("Realtime arrival archive retention purge completed. deletedRows={}", deleted);
	}
}
