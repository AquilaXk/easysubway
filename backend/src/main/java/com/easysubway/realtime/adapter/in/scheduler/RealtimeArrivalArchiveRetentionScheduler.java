package com.easysubway.realtime.adapter.in.scheduler;

import com.easysubway.realtime.application.port.out.RealtimeArrivalArchivePort;
import java.time.Instant;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
@Profile("prod | staging | release | prod-like")
public class RealtimeArrivalArchiveRetentionScheduler {

	private final RealtimeArrivalArchivePort archivePort;

	public RealtimeArrivalArchiveRetentionScheduler(RealtimeArrivalArchivePort archivePort) {
		this.archivePort = archivePort;
	}

	@Scheduled(
		cron = "${easysubway.realtime.archive.purge.cron:0 20 3 * * *}",
		zone = "UTC"
	)
	void purgeExpiredObservations() {
		archivePort.deleteExpired(Instant.now());
	}
}
