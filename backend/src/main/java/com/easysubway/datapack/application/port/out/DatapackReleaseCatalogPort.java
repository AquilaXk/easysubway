package com.easysubway.datapack.application.port.out;

import java.util.Optional;

public interface DatapackReleaseCatalogPort {
	CatalogIdentity fetch(String channel, long releaseSequence);

	CatalogIdentity fetchCurrent(String channel);

	Optional<CatalogIdentity> findByRequest(String channel, String releaseRequestId);

	record CatalogIdentity(long releaseSequence, String manifestSha256, String channel, String releaseRequestId,
		boolean signatureValid, String signatureSha256) {}

	class Unavailable extends RuntimeException {
		public Unavailable() { super("datapack release catalog unavailable"); }
	}

	final class NotFound extends Unavailable {
		public NotFound() { super(); }
	}
}
