package com.easysubway.datapack.application.service;

import com.easysubway.datapack.application.port.out.DatapackReleaseChannelCommandPort;
import com.easysubway.datapack.application.port.out.DatapackReleaseRequestRepository;
import com.easysubway.datapack.adapter.out.persistence.JdbcDatapackReleaseDeliveryRepository;
import com.easysubway.datapack.application.service.CallbackSignature.CanonicalFields;
import com.easysubway.datapack.application.service.DatapackReleaseChannelCommandService.ReleaseChannelCommand;
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
    private final JdbcDatapackReleaseDeliveryRepository deliveryRepository;

    public DatapackReleaseCallbackService(DatapackReleaseRequestRepository repository,
        CallbackSignature signature, ObjectProvider<Clock> clockProvider,
        DatapackReleaseChannelCommandPort channelCommandPort,
        DatapackReleasePromoteDelegate promoteDelegate,
        JdbcDatapackReleaseDeliveryRepository deliveryRepository) {
        this.repository = repository;
        this.signature = signature;
        this.clock = clockProvider.getIfAvailable(Clock::systemDefaultZone);
        this.channelCommandPort = channelCommandPort;
        this.promoteDelegate = promoteDelegate;
        this.deliveryRepository = deliveryRepository;
    }

    @Transactional
    public CallbackResult receive(CallbackCommand cmd) {
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
            deliveryRepository.mark(existingSequence.get().idempotencyKey(), State.DEAD_LETTER,
                existingSequence.get().attempts(), null, "CONFLICT", "MANIFEST_IDENTITY_MISMATCH", now);
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

        boolean pass = "PASS".equals(cmd.publishStatus());
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

	private static String expectedIdempotencyKey(CallbackCommand cmd) {
		return cmd.releaseRequestId() + ":" + cmd.releaseSequence() + ":" + cmd.manifestSha256();
	}

    private void tryPromote(DatapackReleaseRequest r, CallbackCommand cmd) {
        try {
            var channel = channelCommandPort.findChannel(r.targetChannel())
                .orElseThrow(() -> new IllegalStateException(r.targetChannel() + " channel missing"));
            promoteDelegate.promote(new ReleaseChannelCommand(
                r.targetChannel(), channel.candidateId(), r.candidateId(),
                channel.manifestSha256(), cmd.manifestSha256(),
                r.requestedBy(), r.approvedBy(), "auto-promote via release callback",
                "callback:" + r.approvalId(), cmd.workflowRunUrl(), cmd.evidenceBundleSha256()));
            repository.save(r.withPromoteOutcome("SUCCEEDED", null));
        } catch (RuntimeException e) {
            log.warn("auto-promote rejected for {}: {}", r.approvalId(), e.getMessage());
            repository.save(r.withPromoteOutcome("REJECTED", e.getMessage()));
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
