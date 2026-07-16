package com.easysubway.datapack.application.port.out;

import com.easysubway.datapack.domain.DatapackReleaseRequest;
import com.easysubway.datapack.domain.DatapackReleaseRequestStatus;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface DatapackReleaseRequestRepository {

	void save(DatapackReleaseRequest request);

	Optional<DatapackReleaseRequest> findByApprovalId(String approvalId);

	List<DatapackReleaseRequest> findRecent(int limit);

	default List<DatapackReleaseRequest> findReconciliationDue(LocalDateTime cutoff) {
		return findRecent(Integer.MAX_VALUE).stream()
			.filter(request -> request.status() == DatapackReleaseRequestStatus.APPROVED
				|| request.status() == DatapackReleaseRequestStatus.DISPATCHED)
			.filter(request -> !request.updatedAt().isAfter(cutoff))
			.toList();
	}
}
