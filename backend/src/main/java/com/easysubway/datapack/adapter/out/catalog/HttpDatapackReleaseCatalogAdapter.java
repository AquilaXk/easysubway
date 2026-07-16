package com.easysubway.datapack.adapter.out.catalog;

import com.easysubway.datapack.application.port.out.DatapackReleaseCatalogPort;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.Signature;
import java.security.spec.X509EncodedKeySpec;
import java.time.Duration;
import java.util.Base64;
import java.util.HexFormat;
import java.util.stream.StreamSupport;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class HttpDatapackReleaseCatalogAdapter implements DatapackReleaseCatalogPort {
	private static final ObjectMapper JSON = new ObjectMapper();
	private static final Duration TIMEOUT = Duration.ofSeconds(10);

	private final HttpClient httpClient;
	private final String baseUrl;
	private final String publicKeyPem;
	private final String keyId;

	@org.springframework.beans.factory.annotation.Autowired
	public HttpDatapackReleaseCatalogAdapter(
		@Value("${easysubway.datapack.catalog-base-url:}") String baseUrl,
		@Value("${easysubway.datapack.signing-public-key-pem:}") String publicKeyPem,
		@Value("${easysubway.datapack.signing-key-id:production-v1}") String keyId) {
		this(HttpClient.newBuilder().connectTimeout(TIMEOUT).build(), baseUrl, publicKeyPem, keyId);
	}

	HttpDatapackReleaseCatalogAdapter(HttpClient httpClient, String baseUrl, String publicKeyPem, String keyId) {
		this.httpClient = httpClient;
		this.baseUrl = baseUrl == null ? "" : baseUrl.replaceFirst("/+$", "");
		this.publicKeyPem = publicKeyPem == null ? "" : publicKeyPem.trim();
		this.keyId = keyId;
	}

	@Override
	public CatalogIdentity fetch(String channel, long releaseSequence) {
		return fetchPath("/catalog/releases/" + releaseSequence + ".json");
	}

	@Override
	public CatalogIdentity fetchCurrent(String channel) {
		return fetchPath("/catalog/current.json");
	}

	private CatalogIdentity fetchPath(String path) {
		if (baseUrl.isBlank() || publicKeyPem.isBlank()) throw new Unavailable();
		try {
			var request = HttpRequest.newBuilder(URI.create(baseUrl + path))
				.timeout(TIMEOUT).GET().build();
			var response = httpClient.send(request, HttpResponse.BodyHandlers.ofByteArray());
			if (response.statusCode() < 200 || response.statusCode() >= 300) throw new Unavailable();
			byte[] bytes = response.body();
			JsonNode manifest = JSON.readTree(bytes);
			String signatureValue = manifest.path("signature").path("value").asText("");
			boolean signatureValid = "rsa-sha256-manifest-v2".equals(
				manifest.path("signature").path("algorithm").asText())
				&& keyId.equals(manifest.path("keyId").asText())
				&& verify(manifest, signatureValue);
			return new CatalogIdentity(
				manifest.path("releaseSequence").asLong(-1), sha256(bytes),
				manifest.path("channel").asText(""), signatureValid,
				sha256(signatureValue.getBytes(StandardCharsets.UTF_8)));
		} catch (IOException | InterruptedException | RuntimeException exception) {
			if (exception instanceof InterruptedException) Thread.currentThread().interrupt();
			if (exception instanceof Unavailable unavailable) throw unavailable;
			throw new Unavailable();
		}
	}

	private boolean verify(JsonNode manifest, String signatureValue) {
		try {
			var verifier = Signature.getInstance("SHA256withRSA");
			verifier.initVerify(KeyFactory.getInstance("RSA").generatePublic(
				new X509EncodedKeySpec(pemBytes(publicKeyPem))));
			var unsigned = (ObjectNode) manifest.deepCopy();
			unsigned.remove("signature");
			verifier.update(canonical(unsigned));
			return verifier.verify(Base64.getUrlDecoder().decode(signatureValue));
		} catch (java.security.GeneralSecurityException | IllegalArgumentException exception) {
			return false;
		}
	}

	static byte[] canonical(JsonNode value) {
		return canonicalText(value).getBytes(StandardCharsets.UTF_8);
	}

	private static String canonicalText(JsonNode value) {
		if (value.isObject()) {
			return "{" + StreamSupport.stream(
				java.util.Spliterators.spliteratorUnknownSize(value.fieldNames(), 0), false)
				.sorted()
				.map(name -> quoted(name) + ":" + canonicalText(value.get(name)))
				.collect(java.util.stream.Collectors.joining(",")) + "}";
		}
		if (value.isArray()) {
			return "[" + StreamSupport.stream(value.spliterator(), false)
				.map(HttpDatapackReleaseCatalogAdapter::canonicalText)
				.collect(java.util.stream.Collectors.joining(",")) + "]";
		}
		return value.isTextual() ? quoted(value.textValue()) : value.toString();
	}

	private static String quoted(String value) {
		try {
			return JSON.writeValueAsString(value);
		} catch (IOException impossible) {
			throw new IllegalStateException(impossible);
		}
	}

	private static byte[] pemBytes(String pem) {
		return Base64.getMimeDecoder().decode(pem
			.replace("-----BEGIN PUBLIC KEY-----", "")
			.replace("-----END PUBLIC KEY-----", ""));
	}

	private static String sha256(byte[] value) {
		try {
			return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value));
		} catch (java.security.GeneralSecurityException impossible) {
			throw new IllegalStateException(impossible);
		}
	}
}
