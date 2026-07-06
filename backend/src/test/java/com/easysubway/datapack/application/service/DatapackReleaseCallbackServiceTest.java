package com.easysubway.datapack.application.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.easysubway.datapack.application.service.CallbackSignature.CanonicalFields;
import com.easysubway.datapack.application.service.DatapackReleaseCallbackService.CallbackCommand;
import com.easysubway.datapack.application.service.DatapackReleaseCallbackService.CallbackResult;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;

@SpringBootTest
@DisplayName("DatapackReleaseCallbackService")
class DatapackReleaseCallbackServiceTest {

    private static final String SHA = "a".repeat(64);
    private static final String APPROVAL_ID = "release-request-callback-test-1";
    private static final String WORKFLOW_URL = "https://github.com/example/actions/runs/9001";
    private static final LocalDateTime T0 = LocalDateTime.parse("2026-07-06T00:00:00");

    @Autowired
    private DatapackReleaseCallbackService service;
    @Autowired
    private JdbcTemplate jdbcTemplate;
    @Autowired
    private CallbackSignature callbackSignature;

    @BeforeEach
    void setUp() {
        jdbcTemplate.update(
            "DELETE FROM datapack_release_request WHERE approval_id = ?", APPROVAL_ID);
    }

    private void insertRow(String status) {
        jdbcTemplate.update(
            "INSERT INTO datapack_release_request "
                + "(approval_id, candidate_id, scope_id, target_channel, "
                + "build_spec_sha256, source_snapshot_set_hash, approved_ledger_hash, "
                + "requested_by, approved_by, status, dispatch_idempotency_key, workflow_run_url, "
                + "created_at, approved_at, updated_at, promote_outcome, promote_detail) "
                + "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            APPROVAL_ID, "cand-1", "scope-1", "staging",
            SHA, SHA, SHA,
            "alice", "bob", status, "idem-key", null,
            Timestamp.valueOf(T0), Timestamp.valueOf(T0), Timestamp.valueOf(T0),
            null, null);
    }

    private String computeSignature(String publishStatus) {
        var fields = new CanonicalFields(1, "datapack-release-callback", APPROVAL_ID,
            WORKFLOW_URL, SHA, SHA, SHA, SHA, "PASS", "PASS", publishStatus);
        return callbackSignature.sign(fields);
    }

    private CallbackCommand command(String publishStatus, String verifierValue) {
        return new CallbackCommand(1, "datapack-release-callback", APPROVAL_ID,
            WORKFLOW_URL, SHA, SHA, SHA, SHA, "PASS", "PASS", publishStatus,
            "payload-signature", verifierValue);
    }

    @Test
    @DisplayName("(a) 유효 HMAC + DISPATCHED + publishStatus=PASS → PUBLISHED, workflow_run_url 저장")
    void validHmacDispatchedPass() {
        insertRow("DISPATCHED");
        String sig = computeSignature("PASS");
        CallbackResult result = service.receive(command("PASS", sig));
        assertThat(result.status()).isEqualTo("PUBLISHED");
        assertThat(result.idempotentReplay()).isFalse();
        assertThat(statusOf()).isEqualTo("PUBLISHED");
        assertThat(workflowRunUrlOf()).isEqualTo(WORKFLOW_URL);
    }

    @Test
    @DisplayName("(b) 위조 HMAC → IllegalArgumentException(verifier)")
    void forgedHmacThrows() {
        insertRow("DISPATCHED");
        assertThatThrownBy(() -> service.receive(command("PASS", "deadbeef")))
            .isInstanceOf(IllegalArgumentException.class)
            .hasMessageContaining("verifier");
    }

    @Test
    @DisplayName("(c) publishStatus=FAIL → FAILED, promote_detail에 사유")
    void publishFailMarksFailed() {
        insertRow("DISPATCHED");
        String sig = computeSignature("FAIL");
        CallbackResult result = service.receive(command("FAIL", sig));
        assertThat(result.status()).isEqualTo("FAILED");
        assertThat(result.idempotentReplay()).isFalse();
        assertThat(statusOf()).isEqualTo("FAILED");
        assertThat(promoteDetailOf()).contains("FAIL");
    }

    @Test
    @DisplayName("(d) 이미 PUBLISHED + 동일 payload 재수신 → idempotentReplay=true, 상태 불변")
    void alreadyPublishedIdempotentReplay() {
        insertRow("PUBLISHED");
        String sig = computeSignature("PASS");
        CallbackResult result = service.receive(command("PASS", sig));
        assertThat(result.idempotentReplay()).isTrue();
        assertThat(result.status()).isEqualTo("PUBLISHED");
        assertThat(statusOf()).isEqualTo("PUBLISHED");
    }

    @Test
    @DisplayName("(e) status=REQUESTED(미승인) → IllegalStateException")
    void requestedStatusThrowsIllegalState() {
        insertRow("REQUESTED");
        String sig = computeSignature("PASS");
        assertThatThrownBy(() -> service.receive(command("PASS", sig)))
            .isInstanceOf(IllegalStateException.class);
    }

    @Test
    @DisplayName("(f) APPROVED 상태 콜백(수동 dispatch) + PASS → PUBLISHED")
    void approvedStateCallbackPass() {
        insertRow("APPROVED");
        String sig = computeSignature("PASS");
        CallbackResult result = service.receive(command("PASS", sig));
        assertThat(result.status()).isEqualTo("PUBLISHED");
        assertThat(result.idempotentReplay()).isFalse();
        assertThat(statusOf()).isEqualTo("PUBLISHED");
    }

    private String statusOf() {
        return jdbcTemplate.queryForObject(
            "SELECT status FROM datapack_release_request WHERE approval_id = ?",
            String.class, APPROVAL_ID);
    }

    private String workflowRunUrlOf() {
        return jdbcTemplate.queryForObject(
            "SELECT workflow_run_url FROM datapack_release_request WHERE approval_id = ?",
            String.class, APPROVAL_ID);
    }

    private String promoteDetailOf() {
        return jdbcTemplate.queryForObject(
            "SELECT promote_detail FROM datapack_release_request WHERE approval_id = ?",
            String.class, APPROVAL_ID);
    }

    @TestConfiguration
    static class CallbackSignatureTestConfig {

        // 메인 callbackSignature 빈과 이름이 달라야 BeanDefinitionOverrideException 없이 공존 가능.
        // @Primary로 autowiring 우선순위를 획득한다.
        @Bean("testCallbackSignature")
        @Primary
        CallbackSignature testCallbackSignature() {
            return new CallbackSignature("test-callback-hmac-key");
        }
    }
}
