package com.easysubway.datapack.application.service;

import com.easysubway.datapack.adapter.out.persistence.JdbcDatapackReleaseDeliveryRepository;
import com.easysubway.datapack.application.port.out.DatapackReleaseCatalogPort;
import com.easysubway.datapack.application.port.out.DatapackReleaseCatalogPort.CatalogIdentity;
import com.easysubway.datapack.application.port.out.DatapackReleaseChannelCommandPort;
import com.easysubway.datapack.application.port.out.DatapackReleaseRequestRepository;
import com.easysubway.datapack.domain.DatapackReleaseRequestStatus;
import com.easysubway.datapack.domain.DatapackReleaseDelivery;
import com.easysubway.datapack.domain.DatapackReleaseDelivery.State;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;

@Service
public class DatapackReleaseReconciliationService {
	private final JdbcDatapackReleaseDeliveryRepository repository;
	private final DatapackReleaseCallbackService callbackService;
	private final DatapackReleaseCatalogPort catalog;
	private final Clock clock;
	private final DatapackReleaseRequestRepository requestRepository;
	private final DatapackReleaseChannelCommandPort channelRepository;

	@org.springframework.beans.factory.annotation.Autowired
	public DatapackReleaseReconciliationService(JdbcDatapackReleaseDeliveryRepository repository,
		DatapackReleaseCallbackService callbackService, DatapackReleaseCatalogPort catalog,
		DatapackReleaseRequestRepository requestRepository,
		DatapackReleaseChannelCommandPort channelRepository,
		ObjectProvider<Clock> clockProvider) {
		this(repository, callbackService, catalog, requestRepository, channelRepository,
			clockProvider.getIfAvailable(Clock::systemUTC));
	}

	DatapackReleaseReconciliationService(JdbcDatapackReleaseDeliveryRepository repository,
		DatapackReleaseCallbackService callbackService, DatapackReleaseCatalogPort catalog) {
		this(repository, callbackService, catalog, null, null, Clock.systemUTC());
	}

	DatapackReleaseReconciliationService(JdbcDatapackReleaseDeliveryRepository repository,
		DatapackReleaseCallbackService callbackService, DatapackReleaseCatalogPort catalog,
		DatapackReleaseRequestRepository requestRepository,
		DatapackReleaseChannelCommandPort channelRepository) {
		this(repository, callbackService, catalog, requestRepository, channelRepository, Clock.systemUTC());
	}

	private DatapackReleaseReconciliationService(JdbcDatapackReleaseDeliveryRepository repository,
		DatapackReleaseCallbackService callbackService, DatapackReleaseCatalogPort catalog,
		DatapackReleaseRequestRepository requestRepository,
		DatapackReleaseChannelCommandPort channelRepository, Clock clock) {
		this.repository = repository;
		this.callbackService = callbackService;
		this.catalog = catalog;
		this.clock = clock;
		this.requestRepository = requestRepository;
		this.channelRepository = channelRepository;
	}

	public void reconcileDue() {
		var now = LocalDateTime.now(clock);
		discoverMissing(now);
		for (var delivery : repository.claimDue(now, "datapack-reconciler")) {
			reconcile(delivery, now);
		}
	}

	void discoverMissing(LocalDateTime now) {
		if (requestRepository == null || channelRepository == null) return;
		requestRepository.findRecent(100).stream()
			.filter(request -> request.status() == DatapackReleaseRequestStatus.DISPATCHED)
			.filter(request -> !request.updatedAt().isAfter(now.minusMinutes(10)))
			.forEach(request -> {
				try {
					var identity = catalog.fetchCurrent(request.targetChannel());
					if (!identity.signatureValid()
						|| !request.targetChannel().equals(identity.channel())
						|| !channelRepository.candidateHasManifest(
							request.candidateId(), identity.manifestSha256())) return;
					repository.upsertSameDelivery(DatapackReleaseDelivery.pending(
						request.approvalId(), identity.releaseSequence(), identity.manifestSha256(),
						request.targetChannel(), request.candidateId(), identity.manifestSha256(),
						identity.signatureSha256(), now));
				} catch (DatapackReleaseCatalogPort.Unavailable ignored) {
					// fail closed: 다음 bounded scheduler tick에서 재시도한다.
				}
			});
	}

	void reconcile(DatapackReleaseDelivery delivery, LocalDateTime now) {
		try {
			CatalogIdentity identity = catalog.fetch(delivery.channel(), delivery.releaseSequence());
			String mismatch = mismatch(delivery, identity);
			if (mismatch != null) {
				repository.mark(delivery.idempotencyKey(), State.DEAD_LETTER, delivery.attempts(),
					null, "CONFLICT", mismatch, now);
				return;
			}
			callbackService.reconcile(delivery, identity);
		} catch (DatapackReleaseCatalogPort.Unavailable unavailable) {
			if (!now.isBefore(delivery.deadLetterDeadline())) {
				repository.mark(delivery.idempotencyKey(), State.DEAD_LETTER, delivery.attempts(),
					null, "UNAVAILABLE", "CATALOG_UNAVAILABLE", now);
			} else {
				repository.mark(delivery.idempotencyKey(), State.RETRY_SCHEDULED,
					delivery.attempts() + 1, now.plusMinutes(5), "UNAVAILABLE",
					"CATALOG_UNAVAILABLE", now);
			}
		}
	}

	private static String mismatch(DatapackReleaseDelivery delivery, CatalogIdentity identity) {
		if (!identity.signatureValid()) return "CATALOG_SIGNATURE_MISMATCH";
		if (identity.releaseSequence() != delivery.releaseSequence()) return "CATALOG_SEQUENCE_MISMATCH";
		if (!identity.channel().equals(delivery.channel())) return "CATALOG_CHANNEL_MISMATCH";
		if (!identity.manifestSha256().equals(delivery.manifestSha256())) return "CATALOG_MANIFEST_MISMATCH";
		return null;
	}
}
