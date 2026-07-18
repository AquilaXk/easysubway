package com.easysubway.train.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.train.application.TrainSearchCache.CachedCatalog;
import com.easysubway.train.application.TrainSearchCache.CachedLeg;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.aop.framework.ProxyFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.transaction.annotation.AnnotationTransactionAttributeSource;
import org.springframework.transaction.interceptor.TransactionInterceptor;

class JdbcTrainSearchCacheTest {

	private JdbcTrainSearchCache repository;
	private JdbcTemplate jdbcTemplate;
	private DriverManagerDataSource dataSource;

	@BeforeEach
	void setUp() {
		dataSource = new DriverManagerDataSource(
			"jdbc:h2:mem:train-search-cache-" + UUID.randomUUID()
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
		repository = proxiedRepository();
	}

	@Test
	void replacesCatalogAtomicallyAndReadsOnlyFreshRows() {
		Instant observedAt = Instant.parse("2026-07-19T00:00:00Z");
		Instant expiresAt = observedAt.plus(Duration.ofHours(24));
		var stations = new CachedCatalog("stations", "[{\"id\":\"NAT010000\"}]", hash('a'), observedAt, expiresAt);
		var trainTypes = new CachedCatalog("train-types", "[{\"code\":\"KTX\"}]", hash('b'), observedAt, expiresAt);

		repository.replaceCatalog(List.of(stations, trainTypes));

		assertThat(repository.freshCatalog("stations", observedAt.plusSeconds(1))).contains(stations);
		assertThat(repository.freshCatalog("stations", expiresAt)).isEmpty();
		assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM train_catalog_cache", Integer.class))
			.isEqualTo(2);
	}

	@Test
	void leaseHasSingleOwnerAndOnlyOwnerCanRelease() {
		Instant now = Instant.parse("2026-07-19T00:00:00Z");
		assertThat(repository.tryAcquireLease("key", "owner-a", now, Duration.ofSeconds(15))).isTrue();
		assertThat(repository.tryAcquireLease("key", "owner-b", now, Duration.ofSeconds(15))).isFalse();

		repository.releaseLease("key", "owner-b");
		assertThat(repository.tryAcquireLease("key", "owner-b", now, Duration.ofSeconds(15))).isFalse();
		repository.releaseLease("key", "owner-a");
		assertThat(repository.tryAcquireLease("key", "owner-b", now, Duration.ofSeconds(15))).isTrue();
	}

	@Test
	void concurrentLeaseAttemptsHaveExactlyOneOwner() throws InterruptedException {
		int callers = 8;
		var ready = new CountDownLatch(callers);
		var start = new CountDownLatch(1);
		var acquired = new AtomicInteger();
		var failed = new AtomicInteger();
		var completed = new AtomicInteger();
		var executor = Executors.newFixedThreadPool(callers);
		try {
			for (int index = 0; index < callers; index++) {
				String owner = "owner-" + index;
				executor.submit(() -> {
					ready.countDown();
					start.await();
					try {
						if (repository.tryAcquireLease(
							"shared-key",
							owner,
							Instant.parse("2026-07-19T00:00:00Z"),
							Duration.ofSeconds(15)
						)) {
							acquired.incrementAndGet();
						}
					} catch (RuntimeException exception) {
						failed.incrementAndGet();
					}
					completed.incrementAndGet();
					return null;
				});
			}
			assertThat(ready.await(5, TimeUnit.SECONDS)).isTrue();
			start.countDown();
			executor.shutdown();
			assertThat(executor.awaitTermination(10, TimeUnit.SECONDS)).isTrue();
			assertThat(completed).hasValue(callers);
			assertThat(failed).hasValue(0);
			assertThat(acquired).hasValue(1);
		} finally {
			executor.shutdownNow();
		}
	}

	@Test
	void ownerStoresFreshLegAndPurgeRemovesOnlyOldExpiredRows() {
		Instant observedAt = Instant.parse("2026-07-19T00:00:00Z");
		var expired = leg("expired", observedAt, observedAt.plusSeconds(60));
		var fresh = leg("fresh", observedAt, observedAt.plus(Duration.ofHours(6)));
		assertThat(repository.tryAcquireLease("expired", "owner", observedAt, Duration.ofSeconds(15))).isTrue();
		assertThat(repository.storeLegAndRelease("expired", "owner", expired)).isTrue();
		assertThat(repository.tryAcquireLease("fresh", "owner", observedAt, Duration.ofSeconds(15))).isTrue();
		assertThat(repository.storeLegAndRelease("fresh", "owner", fresh)).isTrue();

		assertThat(repository.freshLeg("expired", observedAt.plusSeconds(60))).isEmpty();
		assertThat(repository.freshLeg("fresh", observedAt.plusSeconds(60))).contains(fresh);
		assertThat(repository.purgeExpiredBefore(observedAt.plusSeconds(61))).isEqualTo(1);
		assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM train_search_cache", Integer.class))
			.isEqualTo(1);
	}

	@Test
	void enforcesSharedMinuteAndDayQuotaPerProvider() {
		ZoneId providerZone = ZoneId.of("Asia/Seoul");
		assertThat(repository.tryAcquireProviderCall("tago-train", providerZone, 2, 2)).isTrue();
		assertThat(repository.tryAcquireProviderCall("tago-train", providerZone, 2, 2)).isTrue();
		assertThat(repository.tryAcquireProviderCall("tago-train", providerZone, 2, 2)).isFalse();
		assertThat(repository.tryAcquireProviderCall("other", providerZone, 1, 1)).isTrue();
	}

	private CachedLeg leg(String key, Instant observedAt, Instant expiresAt) {
		return new CachedLeg(key, "{\"key\":\"" + key + "\"}", "{\"outbound\":[]}", hash('c'), observedAt, expiresAt);
	}

	private String hash(char value) {
		return String.valueOf(value).repeat(64);
	}

	private JdbcTrainSearchCache proxiedRepository() {
		var target = new JdbcTrainSearchCache(jdbcTemplate);
		var proxyFactory = new ProxyFactory(target);
		proxyFactory.setProxyTargetClass(true);
		proxyFactory.addAdvice(new TransactionInterceptor(
			new DataSourceTransactionManager(dataSource),
			new AnnotationTransactionAttributeSource()
		));
		return (JdbcTrainSearchCache) proxyFactory.getProxy();
	}
}
