package com.easysubway.realtime.adapter.in.scheduler;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.realtime.application.port.out.RealtimeArrivalArchivePort;
import com.easysubway.realtime.domain.RealtimeArrivalObservation;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Level;
import org.apache.logging.log4j.core.LogEvent;
import org.apache.logging.log4j.core.LoggerContext;
import org.apache.logging.log4j.core.appender.AbstractAppender;
import org.apache.logging.log4j.core.config.Configuration;
import org.apache.logging.log4j.core.config.LoggerConfig;
import org.apache.logging.log4j.core.config.Property;
import org.apache.logging.log4j.core.layout.PatternLayout;
import org.springframework.scheduling.annotation.Scheduled;

@DisplayName("실시간 도착 archive retention scheduler")
class RealtimeArrivalArchiveRetentionSchedulerTest {

	@Test
	@DisplayName("기본 purge 시각은 매일 03:20 UTC다")
	void declaresDefaultSchedule() throws NoSuchMethodException {
		Scheduled scheduled = RealtimeArrivalArchiveRetentionScheduler.class
			.getDeclaredMethod("purgeExpiredObservations")
			.getAnnotation(Scheduled.class);

		assertThat(scheduled.cron()).isEqualTo("${easysubway.realtime.archive.purge.cron:0 20 3 * * *}");
		assertThat(scheduled.zone()).isEqualTo("UTC");
	}

	@Test
	@DisplayName("현재 시각으로 만료 row를 삭제하고 삭제 건수를 기록한다")
	void purgesExpiredRowsAndLogsCount() {
		AtomicReference<Instant> deletedAt = new AtomicReference<>();
		RealtimeArrivalArchivePort archivePort = new RealtimeArrivalArchivePort() {
			@Override
			public void saveAll(List<RealtimeArrivalObservation> observations) {
			}

			@Override
			public int deleteExpired(Instant now) {
				deletedAt.set(now);
				return 7;
			}
		};
		List<String> messages = new ArrayList<>();
		LoggerContext loggerContext = (LoggerContext) LogManager.getContext(false);
		Configuration loggingConfiguration = loggerContext.getConfiguration();
		LoggerConfig loggerConfig = loggingConfiguration.getLoggerConfig(
			RealtimeArrivalArchiveRetentionScheduler.class.getName()
		);
		Level previousLevel = loggerConfig.getLevel();
		loggerConfig.setLevel(Level.INFO);
		AbstractAppender appender = new AbstractAppender(
			"realtime-archive-retention-test",
			null,
			PatternLayout.createDefaultLayout(),
			false,
			Property.EMPTY_ARRAY
		) {
			@Override
			public void append(LogEvent event) {
				messages.add(event.getMessage().getFormattedMessage());
			}
		};
		appender.start();
		loggingConfiguration.addAppender(appender);
		loggerConfig.addAppender(appender, Level.INFO, null);
		loggerContext.updateLoggers();
		Instant before = Instant.now();

		try {
			new RealtimeArrivalArchiveRetentionScheduler(archivePort).purgeExpiredObservations();

			assertThat(deletedAt.get()).isBetween(before, Instant.now());
			assertThat(messages)
				.contains("Realtime arrival archive retention purge completed. deletedRows=7");
		} finally {
			loggerConfig.removeAppender(appender.getName());
			loggerConfig.setLevel(previousLevel);
			loggerContext.updateLoggers();
			appender.stop();
		}
	}
}
