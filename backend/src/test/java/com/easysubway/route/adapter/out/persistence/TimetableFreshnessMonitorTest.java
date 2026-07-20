package com.easysubway.route.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.boot.actuate.health.Status;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

class TimetableFreshnessMonitorTest {

	private static final Instant BEFORE = Instant.parse("2026-07-16T00:00:00Z");
	private static final Instant AFTER = Instant.parse("2026-07-21T00:00:00Z");
	private static final String FRESH_UNTIL = "2026-07-20T00:00:00+09:00";
	private static final String GAUGE = "easysubway.timetable.snapshot.fresh";

	private JdbcTemplate jdbc;

	@BeforeEach
	void setUp() {
		DriverManagerDataSource dataSource = new DriverManagerDataSource(
			"jdbc:h2:mem:freshness-monitor;MODE=PostgreSQL;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE", "sa", "");
		jdbc = new JdbcTemplate(dataSource);
		jdbc.execute("DROP ALL OBJECTS");
		jdbc.execute(
			"CREATE TABLE timetable_snapshot_history (snapshot_sha256 VARCHAR(64) PRIMARY KEY, "
				+ "snapshot_id VARCHAR(120), fresh_until VARCHAR(40))");
		jdbc.execute(
			"CREATE TABLE timetable_snapshot_active (singleton_id INTEGER PRIMARY KEY, snapshot_sha256 VARCHAR(64))");
	}

	@Test
	void reportsFreshWhenActiveSnapshotHasNotExpired() {
		insertActiveSnapshot(FRESH_UNTIL);
		MeterRegistry meterRegistry = new SimpleMeterRegistry();
		TimetableFreshnessMonitor monitor = monitor(BEFORE, meterRegistry);

		monitor.evaluate();

		assertThat(monitor.health().getStatus()).isEqualTo(Status.UP);
		assertThat(monitor.health().getDetails()).containsEntry("state", "FRESH");
		assertThat(meterRegistry.get(GAUGE).gauge().value()).isEqualTo(1.0);
	}

	@Test
	void reportsStaleWhenActiveSnapshotExpiredWithoutRestart() {
		insertActiveSnapshot(FRESH_UNTIL);
		MeterRegistry meterRegistry = new SimpleMeterRegistry();
		TimetableFreshnessMonitor monitor = monitor(AFTER, meterRegistry);

		monitor.evaluate();

		assertThat(monitor.health().getStatus()).isEqualTo(TimetableFreshnessMonitor.STALE);
		assertThat(monitor.health().getDetails())
			.containsEntry("state", "STALE")
			.containsEntry("reason", "route search serves 503 until a fresh snapshot is admitted");
		assertThat(meterRegistry.get(GAUGE).gauge().value()).isEqualTo(0.0);
	}

	@Test
	void reportsUnknownWhenNoActiveSnapshot() {
		MeterRegistry meterRegistry = new SimpleMeterRegistry();
		TimetableFreshnessMonitor monitor = monitor(BEFORE, meterRegistry);

		monitor.evaluate();

		assertThat(monitor.health().getStatus()).isEqualTo(Status.UNKNOWN);
		assertThat(monitor.health().getDetails()).containsEntry("state", "NO_ACTIVE_SNAPSHOT");
		assertThat(meterRegistry.get(GAUGE).gauge().value()).isEqualTo(0.0);
	}

	private TimetableFreshnessMonitor monitor(Instant now, MeterRegistry meterRegistry) {
		return new TimetableFreshnessMonitor(jdbc, Clock.fixed(now, ZoneOffset.UTC), meterRegistry);
	}

	private void insertActiveSnapshot(String freshUntil) {
		jdbc.update(
			"INSERT INTO timetable_snapshot_history (snapshot_sha256, snapshot_id, fresh_until) VALUES (?, ?, ?)",
			"a".repeat(64), "snapshot-a", freshUntil);
		jdbc.update(
			"INSERT INTO timetable_snapshot_active (singleton_id, snapshot_sha256) VALUES (1, ?)", "a".repeat(64));
	}
}
