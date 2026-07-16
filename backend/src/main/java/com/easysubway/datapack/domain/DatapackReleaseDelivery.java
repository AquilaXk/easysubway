package com.easysubway.datapack.domain;

import java.time.LocalDateTime;
import java.util.Locale;
import java.util.regex.Pattern;

public record DatapackReleaseDelivery(
	String idempotencyKey,
	String releaseRequestId,
	long releaseSequence,
	String manifestSha256,
	String channel,
	String candidateId,
	String payloadSha256,
	String signatureSha256,
	State state,
	int attempts,
	LocalDateTime nextAttemptAt,
	LocalDateTime reconcileDeadline,
	LocalDateTime deadLetterDeadline,
	String httpClass,
	String sanitizedDetail,
	LocalDateTime claimedAt,
	String claimOwner,
	LocalDateTime createdAt,
	LocalDateTime updatedAt
) {
	private static final Pattern SHA256 = Pattern.compile("[0-9a-fA-F]{64}");

	public DatapackReleaseDelivery {
		manifestSha256 = sha(manifestSha256, "manifestSha256");
		payloadSha256 = sha(payloadSha256, "payloadSha256");
		signatureSha256 = sha(signatureSha256, "signatureSha256");
		if (releaseSequence < 1) throw new IllegalArgumentException("releaseSequence must be positive");
	}

	public static DatapackReleaseDelivery pending(String releaseRequestId, long releaseSequence,
		String manifestSha256, String channel, String candidateId, String payloadSha256,
		String signatureSha256, LocalDateTime now) {
		return new DatapackReleaseDelivery(
			releaseRequestId + ":" + releaseSequence + ":" + manifestSha256,
			releaseRequestId, releaseSequence, manifestSha256, channel, candidateId,
			payloadSha256, signatureSha256, State.PENDING, 0, now,
			now.plusMinutes(10), now.plusMinutes(70), null, null, null, null, now, now);
	}

	private static String sha(String value, String name) {
		if (value == null || !SHA256.matcher(value).matches()) {
			throw new IllegalArgumentException(name + " must be a sha256 hex string");
		}
		return value.toLowerCase(Locale.ROOT);
	}

	public enum State {
		PENDING, DELIVERED, RETRY_SCHEDULED, RECONCILIATION_REQUIRED, DEAD_LETTER
	}
}
