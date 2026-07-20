package com.easysubway.route.adapter.out.persistence;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import java.time.Clock;
import java.time.OffsetDateTime;
import java.time.format.DateTimeParseException;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicReference;
import javax.sql.DataSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.boot.actuate.health.Status;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * timetable snapshot의 시간 기반 freshness를 런타임에 재평가해 degraded 운용을 관측 가능하게 노출한다.
 *
 * <p>만료 판정은 부팅 한 번이 아니라 주기적으로(그리고 요청 시점의 {@link JdbcRouteTimetableRepository})
 * 이뤄진다. 만료되면 {@code STALE} health 컴포넌트와 gauge(0)로 드러난다. {@code STALE}은 status order상 UP보다
 * 위지만 HTTP 503으로 매핑되지 않고, 이 컴포넌트는 readiness/liveness group에도 포함되지 않으므로
 * admin·상태·복구 엔드포인트와 배포 probe는 영향받지 않는다.
 */
@Component
@Profile("prod | staging | release | prod-like")
class TimetableFreshnessMonitor implements HealthIndicator {

	static final Status STALE = new Status("STALE");
	private static final Logger log = LoggerFactory.getLogger(TimetableFreshnessMonitor.class);

	private final JdbcTemplate jdbcTemplate;
	private final Clock clock;
	private final AtomicReference<Freshness> state = new AtomicReference<>(Freshness.unknown());

	@Autowired
	TimetableFreshnessMonitor(DataSource dataSource, MeterRegistry meterRegistry) {
		this(new JdbcTemplate(dataSource), Clock.systemUTC(), meterRegistry);
	}

	TimetableFreshnessMonitor(JdbcTemplate jdbcTemplate, Clock clock, MeterRegistry meterRegistry) {
		this.jdbcTemplate = jdbcTemplate;
		this.clock = clock;
		Gauge.builder("easysubway.timetable.snapshot.fresh", state, current -> current.get().fresh() ? 1.0 : 0.0)
			.description("Active timetable snapshot freshness: 1 when fresh, 0 when stale or absent")
			.register(meterRegistry);
	}

	@Scheduled(fixedDelayString = "${easysubway.timetable.freshness-check-interval-ms:60000}")
	void evaluate() {
		Freshness previous = state.get();
		Freshness current = current();
		state.set(current);
		logTransition(previous, current);
	}

	@Override
	public Health health() {
		Freshness current = state.get();
		return switch (current.state()) {
			case FRESH -> Health.up()
				.withDetail("state", "FRESH")
				.withDetail("snapshotId", current.snapshotId())
				.withDetail("freshUntil", String.valueOf(current.freshUntil()))
				.build();
			case STALE -> Health.status(STALE)
				.withDetail("state", "STALE")
				.withDetail("snapshotId", current.snapshotId())
				.withDetail("freshUntil", String.valueOf(current.freshUntil()))
				.withDetail("reason", "route search serves 503 until a fresh snapshot is admitted")
				.build();
			case NO_ACTIVE_SNAPSHOT -> Health.unknown()
				.withDetail("state", "NO_ACTIVE_SNAPSHOT")
				.build();
		};
	}

	private Freshness current() {
		try {
			return jdbcTemplate.query(
				"""
					SELECT h.snapshot_id, h.fresh_until
					FROM timetable_snapshot_active a
					JOIN timetable_snapshot_history h ON h.snapshot_sha256 = a.snapshot_sha256
					WHERE a.singleton_id = 1
					""",
				(resultSet, rowNumber) -> Freshness.of(
					resultSet.getString("snapshot_id"),
					resultSet.getString("fresh_until"),
					clock
				)
			).stream().findFirst().orElseGet(Freshness::noActiveSnapshot);
		} catch (RuntimeException exception) {
			log.debug("timetable freshness evaluation skipped: {}", exception.getMessage());
			return Freshness.unknown();
		}
	}

	private void logTransition(Freshness previous, Freshness current) {
		if (previous.state() == State.FRESH && current.state() == State.STALE) {
			log.warn(
				"transit timetable snapshot became stale at {}; route search now serves 503 (degraded) until refresh",
				current.freshUntil()
			);
		} else if (previous.state() == State.STALE && current.state() == State.FRESH) {
			log.info(
				"transit timetable snapshot refreshed (fresh until {}); route search restored",
				current.freshUntil()
			);
		}
	}

	private enum State {
		FRESH,
		STALE,
		NO_ACTIVE_SNAPSHOT
	}

	private record Freshness(State state, String snapshotId, OffsetDateTime freshUntil) {

		private static Freshness of(String snapshotId, String freshUntil, Clock clock) {
			Optional<OffsetDateTime> parsed = parse(freshUntil);
			if (parsed.isEmpty()) {
				return new Freshness(State.STALE, snapshotId, null);
			}
			OffsetDateTime value = parsed.get();
			State state = value.toInstant().isAfter(clock.instant()) ? State.FRESH : State.STALE;
			return new Freshness(state, snapshotId, value);
		}

		private static Freshness noActiveSnapshot() {
			return new Freshness(State.NO_ACTIVE_SNAPSHOT, null, null);
		}

		private static Freshness unknown() {
			return new Freshness(State.NO_ACTIVE_SNAPSHOT, null, null);
		}

		private static Optional<OffsetDateTime> parse(String value) {
			if (value == null || value.isBlank()) {
				return Optional.empty();
			}
			try {
				return Optional.of(OffsetDateTime.parse(value));
			} catch (DateTimeParseException exception) {
				return Optional.empty();
			}
		}

		private boolean fresh() {
			return state == State.FRESH;
		}
	}
}
