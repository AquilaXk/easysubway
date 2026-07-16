package com.easysubway.datapack.application.service;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.easysubway.datapack.adapter.out.persistence.JdbcDatapackReleaseDeliveryRepository;
import com.easysubway.datapack.application.port.out.DatapackReleaseCatalogPort;
import com.easysubway.datapack.application.port.out.DatapackReleaseCatalogPort.CatalogIdentity;
import com.easysubway.datapack.application.port.out.DatapackReleaseChannelCommandPort;
import com.easysubway.datapack.application.port.out.DatapackReleaseRequestRepository;
import com.easysubway.datapack.domain.DatapackReleaseDelivery;
import com.easysubway.datapack.domain.DatapackReleaseDelivery.State;
import com.easysubway.datapack.domain.DatapackReleaseRequest;
import java.time.LocalDateTime;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("DatapackReleaseReconciliationService")
class DatapackReleaseReconciliationServiceTest {
	private static final LocalDateTime T0 = LocalDateTime.parse("2026-07-16T00:00:00");
	private static final String SHA = "a".repeat(64);

	private final JdbcDatapackReleaseDeliveryRepository repository = mock();
	private final DatapackReleaseCallbackService callbackService = mock();
	private final DatapackReleaseCatalogPort catalog = mock();
	private final DatapackReleaseReconciliationService service =
		new DatapackReleaseReconciliationService(repository, callbackService, catalog);

	@Test
	@DisplayName("서명·sequence·hash·channel이 일치하면 callback apply 경로를 재사용한다")
	void matchingCatalogUsesCallbackApply() {
		var delivery = delivery();
		var identity = new CatalogIdentity(42, SHA, "production", true, "b".repeat(64));
		when(catalog.fetch("production", 42)).thenReturn(identity);

		service.reconcile(delivery, T0.plusMinutes(10));

		verify(callbackService).reconcile(delivery, identity);
	}

	@Test
	@DisplayName("catalog signature mismatch는 자동 apply 없이 DEAD_LETTER다")
	void signatureMismatchDeadLetters() {
		var delivery = delivery();
		when(catalog.fetch("production", 42))
			.thenReturn(new CatalogIdentity(42, SHA, "production", false, "b".repeat(64)));

		service.reconcile(delivery, T0.plusMinutes(10));

		verify(repository).mark(delivery.idempotencyKey(), State.DEAD_LETTER, 0, null,
			"CONFLICT", "CATALOG_SIGNATURE_MISMATCH", T0.plusMinutes(10));
	}

	@Test
	@DisplayName("catalog unavailable은 70분 전 retry, 70분 경계부터 DEAD_LETTER다")
	void unavailableHonorsDeadlines() {
		var delivery = delivery();
		when(catalog.fetch("production", 42)).thenThrow(new DatapackReleaseCatalogPort.Unavailable());

		service.reconcile(delivery, T0.plusMinutes(10));
		verify(repository).mark(delivery.idempotencyKey(), State.RETRY_SCHEDULED, 1,
			T0.plusMinutes(15), "UNAVAILABLE", "CATALOG_UNAVAILABLE", T0.plusMinutes(10));

		service.reconcile(delivery, T0.plusMinutes(70));
		verify(repository).mark(delivery.idempotencyKey(), State.DEAD_LETTER, 0, null,
			"UNAVAILABLE", "CATALOG_UNAVAILABLE", T0.plusMinutes(70));
	}

	@Test
	@DisplayName("callback row가 없어도 DISPATCHED request와 current catalog 일치로 delivery를 복원한다")
	void discoversLostCallbackFromCurrentCatalog() {
		var requests = mock(DatapackReleaseRequestRepository.class);
		var channels = mock(DatapackReleaseChannelCommandPort.class);
		var dispatched = DatapackReleaseRequest.requested(
			"request-2057", "candidate-2057", "scope", "production",
			"b".repeat(64), "c".repeat(64), "d".repeat(64), "requester", T0)
			.approve("approver", T0)
			.markDispatched("https://github.com/run/42", "dispatch-42", T0);
		when(requests.findRecent(100)).thenReturn(java.util.List.of(dispatched));
		when(channels.candidateHasManifest("candidate-2057", SHA)).thenReturn(true);
		when(catalog.fetchCurrent("production"))
			.thenReturn(new CatalogIdentity(42, SHA, "production", true, "b".repeat(64)));
		var discovery = new DatapackReleaseReconciliationService(
			repository, callbackService, catalog, requests, channels);

		discovery.discoverMissing(T0.plusMinutes(10));

		verify(repository).upsertSameDelivery(org.mockito.ArgumentMatchers.argThat(delivery ->
			delivery.releaseRequestId().equals("request-2057")
				&& delivery.releaseSequence() == 42
				&& delivery.manifestSha256().equals(SHA)));
	}

	private static DatapackReleaseDelivery delivery() {
		return DatapackReleaseDelivery.pending(
			"request-2057", 42, SHA, "production", "candidate-2057",
			"c".repeat(64), "d".repeat(64), T0);
	}
}
