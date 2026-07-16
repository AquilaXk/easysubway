package com.easysubway.report.adapter.in.scheduler;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.easysubway.report.application.port.out.PurgeFacilityReportPersonalDataPort;
import java.lang.reflect.Method;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.scheduling.annotation.Scheduled;

@DisplayName("시설 신고 개인정보 자동 파기 스케줄러")
class FacilityReportPersonalDataPurgeSchedulerTest {

	@Test
	@DisplayName("일일 실행 지연을 포함해도 기본 1년 보관 상한을 넘기지 않는다")
	void purgesPersonalDataOlderThanRetentionLimit() throws Exception {
		Instant now = Instant.parse("2026-07-16T12:00:00Z");
		AtomicReference<LocalDateTime> cutoff = new AtomicReference<>();
		PurgeFacilityReportPersonalDataPort port = value -> {
			cutoff.set(value);
			return 2;
		};
		var scheduler = new FacilityReportPersonalDataPurgeScheduler(
			port,
			Clock.fixed(now, ZoneOffset.UTC),
			365
		);

		scheduler.purgeExpiredPersonalData();

		assertThat(cutoff.get()).isEqualTo(LocalDateTime.of(2025, 7, 17, 12, 0));
		Method scheduledMethod = FacilityReportPersonalDataPurgeScheduler.class
			.getDeclaredMethod("purgeExpiredPersonalData");
		assertThat(scheduledMethod.getAnnotation(Scheduled.class).fixedDelayString())
			.isEqualTo("${easysubway.report.personal-data-purge-interval-ms:86400000}");
	}

	@Test
	@DisplayName("보관 기간은 하루 이상이어야 한다")
	void rejectsInvalidRetentionDays() {
		assertThatThrownBy(() -> new FacilityReportPersonalDataPurgeScheduler(
			cutoff -> 0,
			Clock.systemUTC(),
			0
		)).isInstanceOf(IllegalArgumentException.class);
	}

	@Test
	@DisplayName("보관 기간은 공개된 최대 365일을 넘을 수 없다")
	void rejectsRetentionDaysAbovePublishedMaximum() {
		assertThatThrownBy(() -> new FacilityReportPersonalDataPurgeScheduler(
			cutoff -> 0,
			Clock.systemUTC(),
			366
		)).isInstanceOf(IllegalArgumentException.class);
	}
}
