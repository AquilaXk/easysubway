package com.easysubway.datapack.application.service;

import com.easysubway.datapack.application.port.out.DatapackReleaseChannelCommandPort;
import com.easysubway.datapack.application.port.out.DatapackReleaseCatalogPort;
import com.easysubway.datapack.application.port.out.DatapackReleaseRequestRepository;
import com.easysubway.datapack.application.port.out.DatapackReleaseDeliveryRepository;
import com.easysubway.datapack.application.service.CallbackSignature.CanonicalFields;
import com.easysubway.datapack.application.service.CallbackSignature.LegacyCanonicalFields;
import com.easysubway.datapack.application.service.DatapackReleaseChannelCommandService.ReleaseChannelCommand;
import com.easysubway.datapack.application.port.out.DatapackReleaseCatalogPort.CatalogIdentity;
import com.easysubway.datapack.domain.DatapackReleaseRequest;
import com.easysubway.datapack.domain.DatapackReleaseRequestStatus;
import com.easysubway.datapack.domain.DatapackReleaseDelivery;
import com.easysubway.datapack.domain.DatapackReleaseDelivery.State;
import java.time.Clock;
import java.time.LocalDateTime;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 워크플로가 보낸 release callback payload를 수신해 HMAC 검증 → release request 상태 전이 → 멱등 재수신
 * no-op를 처리한다. PASS 시 production 채널로 best-effort 자동 promote를 시도한다.
 * promote 게이트 거부 시에도 status=PUBLISHED를 유지하고 promote_outcome=REJECTED를 기록한다.
 */
@Service
public class DatapackReleaseCallbackService {

    private static final Logger log = LoggerFactory.getLogger(DatapackReleaseCallbackService.class);

    private final DatapackReleaseRequestRepository repository;
    private final CallbackSignature signature;
    private final Clock clock;
    private final DatapackReleaseChannelCommandPort channelCommandPort;
    private final DatapackReleasePromoteDelegate promoteDelegate;
    private final DatapackReleaseDeliveryRepository deliveryRepository;
    private final DatapackReleaseCatalogPort releaseCatalog;

    public DatapackReleaseCallbackService(DatapackReleaseRequestRepository repository,
        CallbackSignature signature, ObjectProvider<Clock> clockProvider,
        DatapackReleaseChannelCommandPort channelCommandPort,
        DatapackReleasePromoteDelegate promoteDelegate,
        DatapackReleaseDeliveryRepository deliveryRepository,
        DatapackReleaseCatalogPort releaseCatalog) {
        this.repository = repository;
        this.signature = signature;
        this.clock = clockProvider.getIfAvailable(Clock::systemUTC);
        this.channelCommandPort = channelCommandPort;
        this.promoteDelegate = promoteDelegate;
        this.deliveryRepository = deliveryRepository;
        this.releaseCatalog = releaseCatalog;
    }

    @Transactional
    public CallbackResult receive(CallbackCommand cmd) {
		if (cmd.schemaVersion() == 1) {
			return receiveLegacy(cmd);
		}
        // HMAC 검증 — verifierKind 불일치 또는 서명 불일치 시 거부
        var fields = new CanonicalFields(cmd.schemaVersion(), cmd.artifactKind(),
            cmd.releaseRequestId(), cmd.releaseSequence(), cmd.channel(), cmd.idempotencyKey(),
            cmd.workflowRunUrl(), cmd.manifestSha256(), cmd.sqliteSha256(),
            cmd.gzipSha256(), cmd.evidenceBundleSha256(), cmd.validatorStatus(),
            cmd.routeRegressionStatus(), cmd.publishStatus());
        if (cmd.schemaVersion() != 2 || !"datapack-release-callback".equals(cmd.artifactKind())
            || !expectedIdempotencyKey(cmd).equals(cmd.idempotencyKey())
            || !"payload-signature".equals(cmd.verifierKind())
            || !signature.verify(fields, cmd.verifierValue())) {
            throw new IllegalArgumentException("callback verifier mismatch");
        }

        var now = LocalDateTime.now(clock);
        var existingSequence = deliveryRepository.findByRequestAndSequence(
            cmd.releaseRequestId(), cmd.releaseSequence());
        if (existingSequence.isPresent()
            && !existingSequence.get().manifestSha256().equals(cmd.manifestSha256())) {
			if (existingSequence.get().state() != State.DELIVERED) {
				deliveryRepository.mark(existingSequence.get().idempotencyKey(), State.DEAD_LETTER,
					existingSequence.get().attempts(), null, "CONFLICT", "MANIFEST_IDENTITY_MISMATCH", now);
			}
            return new CallbackResult("DEAD_LETTER", false);
        }

        var request = repository.findByApprovalId(cmd.releaseRequestId()).orElse(null);
        var delivery = deliveryRepository.upsertSameDelivery(DatapackReleaseDelivery.pending(
            cmd.releaseRequestId(), cmd.releaseSequence(), cmd.manifestSha256(), cmd.channel(),
            request == null ? "missing-request" : request.candidateId(), fields.payloadSha256(),
            CallbackSignature.sha256(cmd.verifierValue()), now));
        if (request == null) {
            deliveryRepository.mark(delivery.idempotencyKey(), State.DEAD_LETTER,
                delivery.attempts(), null, "NOT_FOUND", "RELEASE_REQUEST_MISSING", now);
            return new CallbackResult("MISSING_REQUEST", false);
        }
        if (!cmd.channel().equals(request.targetChannel())) {
            deliveryRepository.mark(delivery.idempotencyKey(), State.DEAD_LETTER,
                delivery.attempts(), null, "CONFLICT", "CHANNEL_MISMATCH", now);
            return new CallbackResult("DEAD_LETTER", false);
        }
        if (delivery.state() == State.DELIVERED) {
            return new CallbackResult(request.status().name(), true);
        }
        if (delivery.state() == State.DEAD_LETTER) {
            return new CallbackResult("DEAD_LETTER", true);
        }

        boolean pass = "PASS".equals(cmd.publishStatus())
            && "PASS".equals(cmd.validatorStatus())
            && "PASS".equals(cmd.routeRegressionStatus());
		boolean reconciliationRequired = "BLOCKED_EXTERNAL".equals(cmd.publishStatus())
			&& "PASS".equals(cmd.validatorStatus())
			&& "PASS".equals(cmd.routeRegressionStatus());
		if (reconciliationRequired) {
			deliveryRepository.mark(delivery.idempotencyKey(), State.RECONCILIATION_REQUIRED,
				delivery.attempts() + 1, now.plusMinutes(5), "BLOCKED", "BINDING_UNAVAILABLE", now);
			return new CallbackResult("RECONCILIATION_REQUIRED", false);
		}
		if (pass) {
			var currentMismatch = currentReleaseMismatch(cmd);
			if (currentMismatch != null) {
				deliveryRepository.mark(delivery.idempotencyKey(), State.DEAD_LETTER,
					delivery.attempts(), null, currentMismatch.httpClass(), currentMismatch.detail(), now);
				return new CallbackResult("DEAD_LETTER", false);
			}
		}
        var terminal = pass ? DatapackReleaseRequestStatus.PUBLISHED : DatapackReleaseRequestStatus.FAILED;

        // 멱등: 이미 terminal 상태 + 동일 결과 → no-op
        if (request.status() == terminal) {
            deliveryRepository.mark(delivery.idempotencyKey(), State.DELIVERED,
                delivery.attempts() + 1, null, "2XX", null, now);
            return new CallbackResult(terminal.name(), true);
        }

        var status = request.status();
        if (status != DatapackReleaseRequestStatus.APPROVED
            && status != DatapackReleaseRequestStatus.DISPATCHED) {
            throw new IllegalStateException("callback not accepted from state: " + status);
        }

        var updated = pass
            ? request.markPublished(cmd.workflowRunUrl(), now)
            : request.markFailed("publish " + cmd.publishStatus(), now);
        repository.save(updated);

        if (pass) {
            tryPromote(updated, cmd);
        }
		deliveryRepository.mark(delivery.idempotencyKey(), State.DELIVERED,
			delivery.attempts() + 1, null, "2XX", null, now);

        return new CallbackResult(terminal.name(), false);
    }

	private CallbackResult receiveLegacy(CallbackCommand cmd) {
		var fields = new LegacyCanonicalFields(cmd.schemaVersion(), cmd.artifactKind(),
			cmd.releaseRequestId(), cmd.workflowRunUrl(), cmd.manifestSha256(), cmd.sqliteSha256(),
			cmd.gzipSha256(), cmd.evidenceBundleSha256(), cmd.validatorStatus(),
			cmd.routeRegressionStatus(), cmd.publishStatus());
		if (!"datapack-release-callback".equals(cmd.artifactKind())
			|| !"payload-signature".equals(cmd.verifierKind())
			|| !signature.verify(fields, cmd.verifierValue())) {
			throw new IllegalArgumentException("callback verifier mismatch");
		}

		var request = repository.findByApprovalId(cmd.releaseRequestId())
			.orElseThrow(() -> new IllegalArgumentException(
				"release request not found: " + cmd.releaseRequestId()));
		boolean pass = "PASS".equals(cmd.publishStatus());
		var terminal = pass ? DatapackReleaseRequestStatus.PUBLISHED : DatapackReleaseRequestStatus.FAILED;
		if (request.status() == terminal) {
			return new CallbackResult(terminal.name(), true);
		}
		if (request.status() != DatapackReleaseRequestStatus.APPROVED
			&& request.status() != DatapackReleaseRequestStatus.DISPATCHED) {
			throw new IllegalStateException("callback not accepted from state: " + request.status());
		}

		var now = LocalDateTime.now(clock);
		var updated = pass
			? request.markPublished(cmd.workflowRunUrl(), now)
			: request.markFailed("publish " + cmd.publishStatus(), now);
		repository.save(updated);
		if (pass) {
			if (legacyCurrentReleaseMatches(updated, cmd)) {
				tryPromote(updated, cmd.manifestSha256(), cmd.workflowRunUrl(),
					cmd.evidenceBundleSha256(), updated.approvalId());
			} else {
				repository.save(updated.withPromoteOutcome(
					"REJECTED", "LEGACY_CURRENT_RELEASE_MISMATCH"));
			}
		}
		return new CallbackResult(terminal.name(), false);
	}

	private boolean legacyCurrentReleaseMatches(DatapackReleaseRequest request, CallbackCommand cmd) {
		try {
			var current = releaseCatalog.fetchCurrent(request.targetChannel());
			return current.signatureValid()
				&& request.targetChannel().equals(current.channel())
				&& cmd.manifestSha256().equals(current.manifestSha256());
		} catch (RuntimeException e) {
			log.warn("legacy callback current release unavailable for {}", request.approvalId());
			return false;
		}
	}

	private static String expectedIdempotencyKey(CallbackCommand cmd) {
		return cmd.releaseRequestId() + ":" + cmd.releaseSequence() + ":" + cmd.manifestSha256();
	}

	private CurrentReleaseMismatch currentReleaseMismatch(CallbackCommand cmd) {
		var current = releaseCatalog.fetchCurrent(cmd.channel());
		if (!current.signatureValid() || !cmd.channel().equals(current.channel())) {
			return new CurrentReleaseMismatch("CONFLICT", "CATALOG_CURRENT_MISMATCH");
		}
		if (current.releaseSequence() > cmd.releaseSequence()) {
			return new CurrentReleaseMismatch("STALE", "CURRENT_RELEASE_ADVANCED");
		}
		if (current.releaseSequence() < cmd.releaseSequence()) {
			throw new DatapackReleaseCatalogPort.Unavailable();
		}
		if (!current.manifestSha256().equals(cmd.manifestSha256())) {
			return new CurrentReleaseMismatch("CONFLICT", "CATALOG_CURRENT_MISMATCH");
		}
		var binding = releaseCatalog.findByRequest(cmd.channel(), cmd.releaseRequestId())
			.orElseThrow(DatapackReleaseCatalogPort.Unavailable::new);
		if (!binding.signatureValid()
			|| !cmd.releaseRequestId().equals(binding.releaseRequestId())
			|| !cmd.channel().equals(binding.channel())
			|| cmd.releaseSequence() != binding.releaseSequence()
			|| !cmd.manifestSha256().equals(binding.manifestSha256())) {
			return new CurrentReleaseMismatch("CONFLICT", "RELEASE_REQUEST_BINDING_MISMATCH");
		}
		return null;
	}

	private record CurrentReleaseMismatch(String httpClass, String detail) {}

    private void tryPromote(DatapackReleaseRequest r, CallbackCommand cmd) {
		tryPromote(r, cmd.manifestSha256(), cmd.workflowRunUrl(), cmd.evidenceBundleSha256(),
			cmd.idempotencyKey());
	}

	private void tryPromote(DatapackReleaseRequest r, String manifestSha256, String workflowRunUrl,
		String evidenceBundleSha256, String idempotencyKey) {
        try {
            var channel = channelCommandPort.findChannel(r.targetChannel())
                .orElseThrow(() -> new IllegalStateException(r.targetChannel() + " channel missing"));
            promoteDelegate.promote(new ReleaseChannelCommand(
                r.targetChannel(), channel.candidateId(), r.candidateId(),
                channel.manifestSha256(), manifestSha256,
                r.requestedBy(), r.approvedBy(), "auto-promote via release callback",
                "callback:" + idempotencyKey, workflowRunUrl, evidenceBundleSha256));
            repository.save(r.withPromoteOutcome("SUCCEEDED", null));
        } catch (RuntimeException e) {
            log.warn("auto-promote rejected for {}: {}", r.approvalId(), e.getMessage());
            repository.save(r.withPromoteOutcome("REJECTED", e.getMessage()));
        }
    }

	@Transactional
	public CallbackResult reconcile(DatapackReleaseDelivery delivery, CatalogIdentity catalog) {
		var now = LocalDateTime.now(clock);
		var request = repository.findByApprovalId(delivery.releaseRequestId()).orElse(null);
		if (request == null
			|| !request.candidateId().equals(delivery.candidateId())
			|| !request.targetChannel().equals(delivery.channel())
			|| !channelCommandPort.candidateHasManifest(request.candidateId(), catalog.manifestSha256())) {
			markClaimed(delivery, State.DEAD_LETTER, delivery.attempts(), null,
				"CONFLICT", "REQUEST_CATALOG_MISMATCH", now);
			return new CallbackResult("DEAD_LETTER", false);
		}
		var evidence = channelCommandPort.findPassingReleaseEvidence(request.candidateId()).orElse(null);
		if ("production".equals(request.targetChannel()) && evidence == null) {
			markClaimed(delivery, State.DEAD_LETTER, delivery.attempts(), null,
				"CONFLICT", "RELEASE_EVIDENCE_MISSING", now);
			return new CallbackResult("DEAD_LETTER", false);
		}
		var workflowRunUrl = request.workflowRunUrl() != null
			? request.workflowRunUrl()
			: evidence == null ? null : evidence.workflowRunUrl();
		if (workflowRunUrl == null || workflowRunUrl.isBlank()) {
			markClaimed(delivery, State.DEAD_LETTER, delivery.attempts(), null,
				"CONFLICT", "WORKFLOW_RUN_URL_MISSING", now);
			return new CallbackResult("DEAD_LETTER", false);
		}
		if (request.status() != DatapackReleaseRequestStatus.PUBLISHED) {
			if (request.status() != DatapackReleaseRequestStatus.APPROVED
				&& request.status() != DatapackReleaseRequestStatus.DISPATCHED) {
				markClaimed(delivery, State.DEAD_LETTER, delivery.attempts(), null,
					"CONFLICT", "REQUEST_STATE_MISMATCH", now);
				return new CallbackResult("DEAD_LETTER", false);
			}
			request = request.markPublished(workflowRunUrl, now);
			repository.save(request);
			tryPromote(request, catalog.manifestSha256(), workflowRunUrl,
				evidence == null ? null : evidence.evidenceBundleSha256(),
				delivery.idempotencyKey());
		}
		markClaimed(delivery, State.DELIVERED, delivery.attempts() + 1, null,
			"RECONCILED", null, now);
		return new CallbackResult("PUBLISHED", false);
	}

	private void markClaimed(DatapackReleaseDelivery delivery, State state, int attempts,
		LocalDateTime nextAttemptAt, String httpClass, String detail, LocalDateTime now) {
		if (delivery.claimOwner() == null) {
			deliveryRepository.mark(delivery.idempotencyKey(), state, attempts, nextAttemptAt,
				httpClass, detail, now);
		} else {
			deliveryRepository.markClaimed(delivery.idempotencyKey(), delivery.claimOwner(), state,
				attempts, nextAttemptAt, httpClass, detail, now);
		}
	}

    public record CallbackCommand(
        int schemaVersion,
        String artifactKind,
        String releaseRequestId,
        long releaseSequence,
        String channel,
        String idempotencyKey,
        String workflowRunUrl,
        String manifestSha256,
        String sqliteSha256,
        String gzipSha256,
        String evidenceBundleSha256,
        String validatorStatus,
        String routeRegressionStatus,
        String publishStatus,
        String verifierKind,
        String verifierValue
    ) {}

    public record CallbackResult(String status, boolean idempotentReplay) {}
}
