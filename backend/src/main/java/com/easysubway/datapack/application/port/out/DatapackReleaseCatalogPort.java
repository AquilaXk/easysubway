package com.easysubway.datapack.application.port.out;

public interface DatapackReleaseCatalogPort {
	CatalogIdentity fetch(String channel, long releaseSequence);

	CatalogIdentity fetchCurrent(String channel);

	record CatalogIdentity(long releaseSequence, String manifestSha256, String channel, String releaseRequestId,
		boolean signatureValid, String signatureSha256) {}

	final class Unavailable extends RuntimeException {
		public Unavailable() { super("datapack release catalog unavailable"); }
	}
}
