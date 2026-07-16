package com.easysubway.datapack.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.easysubway.datapack.domain.DatapackReleaseDelivery;
import java.time.LocalDateTime;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;

@SpringBootTest
@DisplayName("JdbcDatapackReleaseDeliveryRepository")
class JdbcDatapackReleaseDeliveryRepositoryTest {

	private static final LocalDateTime T0 = LocalDateTime.parse("2026-07-16T00:00:00");
	private static final String SHA = "a".repeat(64);

	@Autowired
	private JdbcDatapackReleaseDeliveryRepository repository;
	@Autowired
	private JdbcTemplate jdbcTemplate;

	@BeforeEach
	void setUp() {
		jdbcTemplate.update("DELETE FROM datapack_release_deliveries");
	}

	@Test
	@DisplayName("동일 composite identity는 한 row로 멱등 저장한다")
	void upsertsSameDelivery() {
		var first = repository.upsertSameDelivery(pending(SHA));
		var second = repository.upsertSameDelivery(pending(SHA));

		assertThat(second.idempotencyKey()).isEqualTo(first.idempotencyKey());
		assertThat(jdbcTemplate.queryForObject(
			"SELECT COUNT(*) FROM datapack_release_deliveries", Integer.class)).isEqualTo(1);
	}

	@Test
	@DisplayName("같은 request/sequence의 다른 manifest hash는 unique constraint로 거부한다")
	void rejectsDifferentHashForSameSequence() {
		repository.upsertSameDelivery(pending(SHA));

		assertThatThrownBy(() -> repository.upsertSameDelivery(pending("b".repeat(64))))
			.isInstanceOf(DataIntegrityViolationException.class);
	}

	@Test
	@DisplayName("동시 claim은 delivery 한 건을 한 worker에게만 준다")
	void claimsDueOnce() throws Exception {
		repository.upsertSameDelivery(pending(SHA));
		var start = new CountDownLatch(1);
		try (var executor = Executors.newFixedThreadPool(2)) {
			var a = executor.submit(() -> { start.await(); return repository.claimDue(T0, "worker-a", 100); });
			var b = executor.submit(() -> { start.await(); return repository.claimDue(T0, "worker-b", 100); });
			start.countDown();
			assertThat(a.get().size() + b.get().size()).isEqualTo(1);
		}
	}

	@Test
	@DisplayName("만료된 worker claim은 재획득하고 이전 worker의 완료 갱신은 거부한다")
	void reclaimsExpiredLease() {
		repository.upsertSameDelivery(pending(SHA));
		assertThat(repository.claimDue(T0, "worker-a", 100)).hasSize(1);
		assertThat(repository.claimDue(T0.plusMinutes(4), "worker-b", 100)).isEmpty();
		assertThat(repository.claimDue(T0.plusMinutes(5), "worker-b", 100)).hasSize(1);
		assertThatThrownBy(() -> repository.markClaimed(
			pending(SHA).idempotencyKey(), "worker-a", DatapackReleaseDelivery.State.DELIVERED,
			1, null, "RECONCILED", null, T0.plusMinutes(5)))
			.isInstanceOf(IllegalStateException.class);
	}

	private static DatapackReleaseDelivery pending(String manifestSha256) {
		return DatapackReleaseDelivery.pending(
			"request-2057", 42, manifestSha256, "production", "candidate-2057",
			"c".repeat(64), "d".repeat(64), T0);
	}
}
