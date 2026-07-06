package com.easysubway.datapack.application.service;

import com.easysubway.datapack.application.port.out.DatapackReleaseRequestRepository;
import com.easysubway.datapack.application.service.CallbackSignature.CanonicalFields;
import com.easysubway.datapack.domain.DatapackReleaseRequestStatus;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 워크플로가 보낸 release callback payload를 수신해 HMAC 검증 → release request 상태 전이 → 멱등 재수신
 * no-op를 처리한다. best-effort promote는 Task 7에서 훅으로 추가한다.
 */
@Service
public class DatapackReleaseCallbackService {

    private final DatapackReleaseRequestRepository repository;
    private final CallbackSignature signature;
    private final Clock clock;

    public DatapackReleaseCallbackService(DatapackReleaseRequestRepository repository,
        CallbackSignature signature, ObjectProvider<Clock> clockProvider) {
        this.repository = repository;
        this.signature = signature;
        this.clock = clockProvider.getIfAvailable(Clock::systemDefaultZone);
    }

    @Transactional
    public CallbackResult receive(CallbackCommand cmd) {
        // HMAC 검증 — verifierKind 불일치 또는 서명 불일치 시 거부
        var fields = new CanonicalFields(cmd.schemaVersion(), cmd.artifactKind(),
            cmd.releaseRequestId(), cmd.workflowRunUrl(), cmd.manifestSha256(), cmd.sqliteSha256(),
            cmd.gzipSha256(), cmd.evidenceBundleSha256(), cmd.validatorStatus(),
            cmd.routeRegressionStatus(), cmd.publishStatus());
        if (!"payload-signature".equals(cmd.verifierKind())
            || !signature.verify(fields, cmd.verifierValue())) {
            throw new IllegalArgumentException("callback verifier mismatch");
        }

        var request = repository.findByApprovalId(cmd.releaseRequestId())
            .orElseThrow(() -> new IllegalArgumentException(
                "release request not found: " + cmd.releaseRequestId()));

        boolean pass = "PASS".equals(cmd.publishStatus());
        var terminal = pass ? DatapackReleaseRequestStatus.PUBLISHED : DatapackReleaseRequestStatus.FAILED;

        // 멱등: 이미 terminal 상태 + 동일 결과 → no-op
        if (request.status() == terminal) {
            return new CallbackResult(terminal.name(), true);
        }

        var status = request.status();
        if (status != DatapackReleaseRequestStatus.APPROVED
            && status != DatapackReleaseRequestStatus.DISPATCHED) {
            throw new IllegalStateException("callback not accepted from state: " + status);
        }

        var now = LocalDateTime.now(clock);
        var updated = pass
            ? request.markPublished(cmd.workflowRunUrl(), now)
            : request.markFailed("publish " + cmd.publishStatus(), now);
        repository.save(updated);

        // TODO(Task 7): best-effort promote 훅 삽입 지점

        return new CallbackResult(terminal.name(), false);
    }

    public record CallbackCommand(
        int schemaVersion,
        String artifactKind,
        String releaseRequestId,
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
