package com.easysubway.datapack.application.service;

import com.easysubway.datapack.application.port.out.DatapackReleaseRequestRepository;
import com.easysubway.datapack.domain.DatapackReleaseRequest;
import com.easysubway.datapack.domain.DatapackReleaseRequestStatus;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DatapackReleaseRequestService {

	private final DatapackReleaseRequestRepository repository;
	private final Clock clock;

	public DatapackReleaseRequestService(
		DatapackReleaseRequestRepository repository,
		ObjectProvider<Clock> clockProvider
	) {
		this.repository = repository;
		this.clock = clockProvider.getIfAvailable(Clock::systemDefaultZone);
	}

	@Transactional
	public DatapackReleaseRequest create(CreateReleaseRequestCommand command) {
		command.validate();
		var now = LocalDateTime.now(clock);
		var request = DatapackReleaseRequest.requested(
			"release-request-" + UUID.randomUUID(),
			command.candidateId(), command.scopeId(), command.targetChannel(),
			command.buildSpecSha256(), command.sourceSnapshotSetHash(), command.approvedLedgerHash(),
			command.requestedBy(), now);
		repository.save(request);
		return request;
	}

	/**
	 * 승인은 레코드 상태 전이까지다 — 여기서 release workflow를 발화하지 않는다(#2564).
	 * 릴리스 승인 권위는 git 파일(release-request.json 변경 PR 병합)과 GitHub Environment
	 * required reviewer가 가지며, 이 레코드는 이력·관측용이다.
	 */
	@Transactional
	public DatapackReleaseRequest approve(String approvalId, String approver) {
		var request = repository.findByApprovalId(approvalId)
			.orElseThrow(() -> new IllegalArgumentException("release request not found: " + approvalId));
		var approved = request.approve(approver, LocalDateTime.now(clock));
		repository.save(approved);
		return approved;
	}

	// 워크플로가 fetch 가능한 상태: 승인됨(APPROVED) + 과거 자동 dispatch로 전이한 DISPATCHED 이력 행.
	// DISPATCHED는 더 이상 backend가 만들지 않지만 기존 행이 남아 있으므로 서빙 대상을 유지한다
	// (read 경로 불변). DISPATCH_FAILED/FAILED 등 미발화·실패 상태는 서빙 대상이 아니다.
	private static final Set<DatapackReleaseRequestStatus> SERVABLE_STATUSES =
		Set.of(DatapackReleaseRequestStatus.APPROVED, DatapackReleaseRequestStatus.DISPATCHED);

	@Transactional(readOnly = true)
	public Optional<DatapackReleaseRequest> findApproved(String approvalId) {
		return repository.findByApprovalId(approvalId)
			.filter(r -> SERVABLE_STATUSES.contains(r.status()));
	}

	public record CreateReleaseRequestCommand(
		String candidateId,
		String scopeId,
		String targetChannel,
		String buildSpecSha256,
		String sourceSnapshotSetHash,
		String approvedLedgerHash,
		String requestedBy
	) {

		private void validate() {
			requireText(candidateId, "candidateId");
			requireText(scopeId, "scopeId");
			requireText(requestedBy, "requestedBy");
			if (!Set.of("dev", "staging", "production").contains(targetChannel)) {
				throw new IllegalArgumentException("targetChannel must be dev|staging|production");
			}
			// sha 형식 검증·소문자 정규화는 도메인 record 생성자가 수행한다.
		}

		private static void requireText(String value, String name) {
			if (value == null || value.isBlank()) {
				throw new IllegalArgumentException(name + " is required");
			}
		}
	}
}
