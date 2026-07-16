package com.easysubway.datapack.application.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.datapack.application.service.CallbackSignature.CanonicalFields;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("CallbackSignature")
class CallbackSignatureTest {

    private static CanonicalFields fields(JsonNode f) {
        return new CanonicalFields(f.get("schemaVersion").asInt(), f.get("artifactKind").asText(),
            f.get("releaseRequestId").asText(), f.get("releaseSequence").asLong(),
			f.get("channel").asText(), f.get("idempotencyKey").asText(), f.get("workflowRunUrl").asText(),
            f.get("manifestSha256").asText(), f.get("sqliteSha256").asText(),
            f.get("gzipSha256").asText(), f.get("evidenceBundleSha256").asText(),
            f.get("validatorStatus").asText(), f.get("routeRegressionStatus").asText(),
            f.get("publishStatus").asText());
    }

    @Test
    @DisplayName("빈 키로 생성된 CallbackSignature의 verify는 false 반환(dormant 경로)")
    void emptyKeyVerifyReturnsFalse() {
        var sig = new CallbackSignature("");
        var f = new CanonicalFields(2, "datapack-release-callback", "req-001", 42,
			"production", "req-001:42:" + "a".repeat(64),
            "https://github.com/example/actions/runs/1",
            "a".repeat(64), "b".repeat(64), "c".repeat(64), "d".repeat(64),
            "PASS", "PASS", "PASS");
        assertThat(sig.verify(f, "any-value")).isFalse();
        assertThat(sig.verify(f, null)).isFalse();
    }

    @Test
    @DisplayName("공유 fixture 벡터의 기대 HMAC과 일치하고 위조는 verify=false")
    void matchesSharedVector() throws Exception {
        var root = Path.of(System.getProperty("user.dir")).getParent(); // backend → repo root
        var node = new ObjectMapper().readTree(
            Files.readString(root.resolve("tools/datapack/fixtures/release-callback-signature-vector.json")));
        var sig = new CallbackSignature(node.get("hmacKey").asText());
        var f = fields(node.get("fields"));

        String expected = node.get("expectedHmacHex").asText();
        assertThat(sig.sign(f)).isEqualTo(expected);
        assertThat(sig.verify(f, expected)).isTrue();
        assertThat(sig.verify(f, "deadbeef")).isFalse();
		assertThat(f.payloadSha256()).isEqualTo("68f79bd7a3d89e10e431019401dd111607c91fc0e61046c5cf1620da09b797c8");
		assertThat(new CanonicalFields(f.schemaVersion(), f.artifactKind(), f.releaseRequestId(), 43,
			f.channel(), f.idempotencyKey(), f.workflowRunUrl(), f.manifestSha256(), f.sqliteSha256(),
			f.gzipSha256(), f.evidenceBundleSha256(), f.validatorStatus(), f.routeRegressionStatus(),
			f.publishStatus()).payloadSha256()).isNotEqualTo(f.payloadSha256());
		assertThat(new CanonicalFields(f.schemaVersion(), f.artifactKind(), f.releaseRequestId(),
			f.releaseSequence(), "staging", f.idempotencyKey(), f.workflowRunUrl(), f.manifestSha256(),
			f.sqliteSha256(), f.gzipSha256(), f.evidenceBundleSha256(), f.validatorStatus(),
			f.routeRegressionStatus(), f.publishStatus()).payloadSha256()).isNotEqualTo(f.payloadSha256());
		assertThat(new CanonicalFields(f.schemaVersion(), f.artifactKind(), f.releaseRequestId(),
			f.releaseSequence(), f.channel(), "different", f.workflowRunUrl(), f.manifestSha256(),
			f.sqliteSha256(), f.gzipSha256(), f.evidenceBundleSha256(), f.validatorStatus(),
			f.routeRegressionStatus(), f.publishStatus()).payloadSha256()).isNotEqualTo(f.payloadSha256());
    }
}
