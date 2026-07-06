package com.easysubway.datapack.adapter.in.web;

import com.easysubway.datapack.adapter.out.persistence.JdbcDatapackCandidateRepository;
import com.easysubway.datapack.adapter.out.persistence.JdbcDatapackCandidateRepository.CandidateRow;
import com.easysubway.datapack.application.port.out.DatapackReleaseRequestRepository;
import com.easysubway.datapack.application.service.DatapackReleaseRequestService;
import com.easysubway.datapack.application.service.DatapackReleaseRequestService.CreateReleaseRequestCommand;
import com.easysubway.datapack.domain.DatapackReleaseRequest;
import java.time.LocalDateTime;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
class DatapackReleaseRequestAdminPageController {

	private static final int CANDIDATE_LIMIT = 20;
	private static final int REQUEST_LIMIT = 20;

	private final JdbcDatapackCandidateRepository candidateRepository;
	private final DatapackReleaseRequestRepository releaseRequestRepository;
	private final DatapackReleaseRequestService releaseRequestService;

	DatapackReleaseRequestAdminPageController(
		JdbcDatapackCandidateRepository candidateRepository,
		DatapackReleaseRequestRepository releaseRequestRepository,
		DatapackReleaseRequestService releaseRequestService
	) {
		this.candidateRepository = candidateRepository;
		this.releaseRequestRepository = releaseRequestRepository;
		this.releaseRequestService = releaseRequestService;
	}

	@GetMapping("/admin/datapack/release-requests/page")
	@PreAuthorize("hasAuthority('admin.datapack.read')")
	String page(Model model) {
		model.addAttribute("candidates", candidateRepository.listRecentCandidates(CANDIDATE_LIMIT).stream()
			.map(CandidateOption::from)
			.toList());
		model.addAttribute("requests", releaseRequestRepository.findRecent(REQUEST_LIMIT).stream()
			.map(ReleaseRequestView::from)
			.toList());
		return "admin/datapack/release-requests/list";
	}

	@PostMapping("/admin/datapack/release-requests")
	@PreAuthorize("hasAuthority('admin.datapack.staging.promote')")
	String create(
		@RequestParam("candidateId") String candidateId,
		@RequestParam("targetChannel") String targetChannel,
		Authentication authentication
	) {
		CandidateRow candidate = candidateRepository.findCandidate(candidateId)
			.orElseThrow(() -> new IllegalArgumentException("candidate not found: " + candidateId));
		// 스펙 A-1: 파생값은 candidate에서 채운다(사용자 자유 입력 아님).
		// approvedLedgerHash ← candidate.overrideSetHash(승인된 오버라이드 장부 해시).
		releaseRequestService.create(new CreateReleaseRequestCommand(
			candidate.id(),
			candidate.scopeId(),
			targetChannel,
			candidate.buildSpecSha256(),
			candidate.sourceSnapshotSetHash(),
			candidate.overrideSetHash(),
			authentication.getName()));
		return "redirect:/admin/datapack/release-requests/page";
	}

	@PostMapping("/admin/datapack/release-requests/{approvalId}/approve")
	@PreAuthorize("hasAuthority('admin.datapack.production.approve')")
	String approve(@PathVariable("approvalId") String approvalId, Authentication authentication) {
		releaseRequestService.approve(approvalId, authentication.getName());
		return "redirect:/admin/datapack/release-requests/page";
	}

	record CandidateOption(String id, String version, String scopeId, String approvalStatus) {
		static CandidateOption from(CandidateRow row) {
			return new CandidateOption(row.id(), row.version(), row.scopeId(), row.approvalStatus());
		}
	}

	record ReleaseRequestView(
		String approvalId,
		String candidateId,
		String scopeId,
		String targetChannel,
		String status,
		String requestedBy,
		String approvedBy,
		LocalDateTime createdAt
	) {
		static ReleaseRequestView from(DatapackReleaseRequest r) {
			return new ReleaseRequestView(
				r.approvalId(), r.candidateId(), r.scopeId(), r.targetChannel(),
				r.status().name(), r.requestedBy(),
				r.approvedBy() == null ? "-" : r.approvedBy(), r.createdAt());
		}
	}
}
