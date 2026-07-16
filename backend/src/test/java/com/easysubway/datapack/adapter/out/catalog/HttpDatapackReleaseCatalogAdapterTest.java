package com.easysubway.datapack.adapter.out.catalog;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.Signature;
import java.util.Base64;
import java.util.HexFormat;
import org.junit.jupiter.api.Test;

class HttpDatapackReleaseCatalogAdapterTest {
	private static final ObjectMapper JSON = new ObjectMapper();

	@Test
	void canonicalNumbersMatchEcmascriptJsonStringify() throws Exception {
		var value = JSON.readTree("""
			{"plainSmall":0.0001,"scientificSmall":0.0000001,"plainLarge":100000000000000000000,"scientificLarge":1e21,"negativeZero":-0.0}
			""");

		assertThat(new String(HttpDatapackReleaseCatalogAdapter.canonical(value), StandardCharsets.UTF_8))
			.isEqualTo("{\"negativeZero\":0,\"plainLarge\":100000000000000000000,\"plainSmall\":0.0001,"
				+ "\"scientificLarge\":1e+21,\"scientificSmall\":1e-7}");
	}

	@Test
	void fetchCurrentFailsClosedWithoutConfiguredTrustMaterial() {
		var adapter = new HttpDatapackReleaseCatalogAdapter("", "", "production-v1");
		assertThatThrownBy(() -> adapter.fetchCurrent("production"))
			.isInstanceOf(com.easysubway.datapack.application.port.out.DatapackReleaseCatalogPort.Unavailable.class);
	}

	@Test
	void verifiesImmutableManifestSignatureAndIdentity() throws Exception {
		var keyPair = KeyPairGenerator.getInstance("RSA").generateKeyPair();
		var manifest = JSON.createObjectNode();
		manifest.put("manifestVersion", 2);
		manifest.put("channel", "production");
		manifest.put("releaseSequence", 42);
		manifest.put("keyId", "production-v1");
		manifest.put("ttlSeconds", 3600);
		manifest.putArray("packs");
		var signer = Signature.getInstance("SHA256withRSA");
		signer.initSign(keyPair.getPrivate());
		signer.update(HttpDatapackReleaseCatalogAdapter.canonical(manifest));
		var signature = manifest.putObject("signature");
		signature.put("algorithm", "rsa-sha256-manifest-v2");
		signature.put("value", Base64.getUrlEncoder().withoutPadding().encodeToString(signer.sign()));
		byte[] body = JSON.writeValueAsBytes(manifest);

		var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/catalog/releases/42.json", exchange -> {
			exchange.sendResponseHeaders(200, body.length);
			exchange.getResponseBody().write(body);
			exchange.close();
		});
		server.start();
		try {
			String publicKey = "-----BEGIN PUBLIC KEY-----\n"
				+ Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII))
					.encodeToString(keyPair.getPublic().getEncoded())
				+ "\n-----END PUBLIC KEY-----";
			var adapter = new HttpDatapackReleaseCatalogAdapter(
				"http://127.0.0.1:" + server.getAddress().getPort(),
				publicKey.replace("\n", "\\n"), "production-v1");

			var identity = adapter.fetch("production", 42);

			assertThat(identity.releaseSequence()).isEqualTo(42);
			assertThat(identity.channel()).isEqualTo("production");
			assertThat(identity.signatureValid()).isTrue();
			assertThat(identity.manifestSha256()).hasSize(64);
		} finally {
			server.stop(0);
		}
	}

	@Test
	void returnsSignedIdentityForServiceMismatchClassification() throws Exception {
		var keyPair = KeyPairGenerator.getInstance("RSA").generateKeyPair();
		var manifest = JSON.createObjectNode();
		manifest.put("manifestVersion", 2);
		manifest.put("channel", "staging");
		manifest.put("releaseSequence", 41);
		manifest.put("keyId", "production-v1");
		manifest.put("ttlSeconds", 3600);
		manifest.putArray("packs");
		var signer = Signature.getInstance("SHA256withRSA");
		signer.initSign(keyPair.getPrivate());
		signer.update(HttpDatapackReleaseCatalogAdapter.canonical(manifest));
		var signature = manifest.putObject("signature");
		signature.put("algorithm", "rsa-sha256-manifest-v2");
		signature.put("value", Base64.getUrlEncoder().withoutPadding().encodeToString(signer.sign()));
		byte[] body = JSON.writeValueAsBytes(manifest);
		var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/catalog/releases/42.json", exchange -> {
			exchange.sendResponseHeaders(200, body.length);
			exchange.getResponseBody().write(body);
			exchange.close();
		});
		server.start();
		try {
			String publicKey = "-----BEGIN PUBLIC KEY-----\n"
				+ Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII))
					.encodeToString(keyPair.getPublic().getEncoded())
				+ "\n-----END PUBLIC KEY-----";
			var adapter = new HttpDatapackReleaseCatalogAdapter(
				"http://127.0.0.1:" + server.getAddress().getPort(), publicKey, "production-v1");
			var identity = adapter.fetch("production", 42);
			assertThat(identity.signatureValid()).isTrue();
			assertThat(identity.channel()).isEqualTo("staging");
			assertThat(identity.releaseSequence()).isEqualTo(41);
		} finally {
			server.stop(0);
		}
	}

	@Test
	void findsRequestThroughSignedBindingWithoutChangingManifestIdentity() throws Exception {
		var keyPair = KeyPairGenerator.getInstance("RSA").generateKeyPair();
		byte[] manifest = signedManifest(keyPair, 42);
		byte[] current = manifest;
		byte[] binding = signedBinding(keyPair, 42, "request-2057", sha256(manifest));
		var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/catalog/release-requests/"
			+ sha256("request-2057".getBytes(StandardCharsets.UTF_8)) + ".json",
			exchange -> respond(exchange, binding));
		server.createContext("/catalog/releases/42.json", exchange -> respond(exchange, manifest));
		server.createContext("/catalog/current.json", exchange -> respond(exchange, current));
		server.start();
		try {
			String publicKey = "-----BEGIN PUBLIC KEY-----\n"
				+ Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII))
					.encodeToString(keyPair.getPublic().getEncoded())
				+ "\n-----END PUBLIC KEY-----";
			var adapter = new HttpDatapackReleaseCatalogAdapter(
				"http://127.0.0.1:" + server.getAddress().getPort(), publicKey, "production-v1");

			var found = adapter.findByRequest("production", "request-2057");

			assertThat(found).get().extracting(identity -> identity.releaseSequence()).isEqualTo(42L);
			assertThat(found).get().extracting(identity -> identity.manifestSha256()).isEqualTo(sha256(manifest));
		} finally {
			server.stop(0);
		}
	}

	@Test
	void rejectsRequestWhenALaterReleaseReplacedTheCurrentPointer() throws Exception {
		var keyPair = KeyPairGenerator.getInstance("RSA").generateKeyPair();
		byte[] manifest = signedManifest(keyPair, 42);
		byte[] current = signedManifest(keyPair, 44);
		byte[] binding = signedBinding(keyPair, 42, "request-2057", sha256(manifest));
		var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/catalog/release-requests/"
			+ sha256("request-2057".getBytes(StandardCharsets.UTF_8)) + ".json",
			exchange -> respond(exchange, binding));
		server.createContext("/catalog/releases/42.json", exchange -> respond(exchange, manifest));
		server.createContext("/catalog/current.json", exchange -> respond(exchange, current));
		server.start();
		try {
			String publicKey = "-----BEGIN PUBLIC KEY-----\n"
				+ Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII))
					.encodeToString(keyPair.getPublic().getEncoded())
				+ "\n-----END PUBLIC KEY-----";
			var adapter = new HttpDatapackReleaseCatalogAdapter(
				"http://127.0.0.1:" + server.getAddress().getPort(), publicKey, "production-v1");

			assertThatThrownBy(() -> adapter.findByRequest("production", "request-2057"))
				.isInstanceOf(com.easysubway.datapack.application.port.out.DatapackReleaseCatalogPort.Unavailable.class);
		} finally {
			server.stop(0);
		}
	}

	private static byte[] signedManifest(java.security.KeyPair keyPair, long sequence)
		throws Exception {
		var manifest = JSON.createObjectNode();
		manifest.put("manifestVersion", 2);
		manifest.put("channel", "production");
		manifest.put("releaseSequence", sequence);
		manifest.put("keyId", "production-v1");
		manifest.put("ttlSeconds", 3600);
		manifest.putArray("packs");
		var signer = Signature.getInstance("SHA256withRSA");
		signer.initSign(keyPair.getPrivate());
		signer.update(HttpDatapackReleaseCatalogAdapter.canonical(manifest));
		var signature = manifest.putObject("signature");
		signature.put("algorithm", "rsa-sha256-manifest-v2");
		signature.put("value", Base64.getUrlEncoder().withoutPadding().encodeToString(signer.sign()));
		return JSON.writeValueAsBytes(manifest);
	}

	private static byte[] signedBinding(java.security.KeyPair keyPair, long sequence,
		String requestId, String manifestSha256) throws Exception {
		var binding = JSON.createObjectNode();
		binding.put("schemaVersion", 1);
		binding.put("artifactKind", "datapack-release-request-binding");
		binding.put("releaseRequestId", requestId);
		binding.put("releaseSequence", sequence);
		binding.put("channel", "production");
		binding.put("manifestSha256", manifestSha256);
		binding.put("keyId", "production-v1");
		var signer = Signature.getInstance("SHA256withRSA");
		signer.initSign(keyPair.getPrivate());
		signer.update(HttpDatapackReleaseCatalogAdapter.canonical(binding));
		var signature = binding.putObject("signature");
		signature.put("algorithm", "rsa-sha256-release-request-v1");
		signature.put("value", Base64.getUrlEncoder().withoutPadding().encodeToString(signer.sign()));
		return JSON.writeValueAsBytes(binding);
	}

	private static String sha256(byte[] value) throws Exception {
		return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(value));
	}

	private static void respond(com.sun.net.httpserver.HttpExchange exchange, byte[] body)
		throws java.io.IOException {
		exchange.sendResponseHeaders(200, body.length);
		exchange.getResponseBody().write(body);
		exchange.close();
	}
}
