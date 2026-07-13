package com.easysubway.realtime.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.time.ZoneId;
import java.util.UUID;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.transaction.annotation.Transactional;

@DisplayName("JDBC realtime provider 공유 quota")
class JdbcRealtimeProviderCallQuotaRepositoryTest {

	private JdbcRealtimeProviderCallQuotaRepository repository;
	private JdbcTemplate jdbcTemplate;

	@BeforeEach
	void setUp() {
		var dataSource = new DriverManagerDataSource(
			"jdbc:h2:mem:realtime-provider-quota-" + UUID.randomUUID()
				+ ";MODE=PostgreSQL;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
			"sa",
			""
		);
		Flyway.configure()
			.dataSource(dataSource)
			.locations("classpath:db/migration/h2")
			.load()
			.migrate();
		jdbcTemplate = new JdbcTemplate(dataSource);
		repository = new JdbcRealtimeProviderCallQuotaRepository(jdbcTemplate);
	}

	@Test
	@DisplayName("새 repository instance도 같은 일일 quota를 이어서 사용한다")
	void persistsDailyQuotaAcrossRepositoryInstances() {
		Instant now = Instant.parse("2026-07-13T01:00:00Z");
		ZoneId providerZone = ZoneId.of("Asia/Seoul");
		assertThat(repository.tryAcquire("seoul-topis", now, providerZone, 10, 2)).isTrue();
		assertThat(repository.tryAcquire("seoul-topis", now.plusSeconds(60), providerZone, 10, 2)).isTrue();

		var restarted = new JdbcRealtimeProviderCallQuotaRepository(jdbcTemplate);
		assertThat(restarted.tryAcquire("seoul-topis", now.plusSeconds(120), providerZone, 10, 2)).isFalse();
	}

	@Test
	@DisplayName("분당 quota도 공유 상태에서 원자적으로 제한한다")
	void enforcesSharedMinuteQuota() {
		Instant now = Instant.parse("2026-07-13T01:00:00Z");
		ZoneId providerZone = ZoneId.of("Asia/Seoul");
		assertThat(repository.tryAcquire("seoul-topis", now, providerZone, 1, 800)).isTrue();
		assertThat(repository.tryAcquire("seoul-topis", now.plusSeconds(30), providerZone, 1, 800)).isFalse();
		assertThat(repository.tryAcquire("seoul-topis", now.plusSeconds(60), providerZone, 1, 800)).isTrue();
	}

	@Test
	@DisplayName("quota 획득은 transaction 경계를 선언한다")
	void declaresTransactionalAcquire() throws NoSuchMethodException {
		assertThat(JdbcRealtimeProviderCallQuotaRepository.class
			.getMethod("tryAcquire", String.class, Instant.class, ZoneId.class, int.class, int.class)
			.getAnnotation(Transactional.class))
			.isNotNull();
	}
}
