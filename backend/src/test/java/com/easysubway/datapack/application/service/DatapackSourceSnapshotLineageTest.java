package com.easysubway.datapack.application.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.easysubway.datapack.adapter.out.persistence.JdbcDataSourceSnapshotRepository;
import com.easysubway.datapack.application.service.DatapackSourceSnapshotCommandService.SourceSnapshotCommand;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DataSourceTransactionManager;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

@DisplayName("데이터팩 source snapshot lineage command")
class DatapackSourceSnapshotLineageTest {

	private DatapackSourceSnapshotCommandService service;

	@BeforeEach
	void setUp() {
		var dataSource = new DriverManagerDataSource(
			"jdbc:h2:mem:datapack-source-lineage;MODE=PostgreSQL;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
			"sa",
			""
		);
		var jdbcTemplate = new JdbcTemplate(dataSource);
		jdbcTemplate.execute("DROP TABLE IF EXISTS datapack_source_snapshot_events");
		jdbcTemplate.execute("DROP TABLE IF EXISTS data_source_snapshots");
		jdbcTemplate.execute("""
			CREATE TABLE data_source_snapshots (
				snapshot_id VARCHAR(120) PRIMARY KEY,
				source_id VARCHAR(120) NOT NULL,
				provider VARCHAR(120) NOT NULL,
				retrieved_at TIMESTAMP NOT NULL,
				source_updated_at TIMESTAMP,
				row_count INTEGER NOT NULL,
				coverage_count INTEGER,
				raw_sha256 VARCHAR(64) NOT NULL,
				raw_object_uri VARCHAR(1000) NOT NULL,
				redacted_request_fingerprint VARCHAR(64) NOT NULL,
				schema_fingerprint VARCHAR(64) NOT NULL,
				snapshot_status VARCHAR(30) NOT NULL,
				schema_status VARCHAR(30) NOT NULL,
				license_status VARCHAR(30) NOT NULL,
				fetch_status VARCHAR(30) NOT NULL,
				redistribution_allowed BOOLEAN NOT NULL,
				credential_redacted BOOLEAN NOT NULL,
				previous_snapshot_id VARCHAR(120),
				diff_summary VARCHAR(1000),
				diff_summary_json CLOB,
				freshness_expires_at TIMESTAMP NOT NULL,
				raw_retention_expires_at TIMESTAMP NOT NULL,
				governance_policy_version VARCHAR(32),
				governance_policy_sha256 VARCHAR(64)
			)
			""");
		jdbcTemplate.execute("""
			CREATE TABLE datapack_source_snapshot_events (
				id VARCHAR(120) PRIMARY KEY,
				source_id VARCHAR(120) NOT NULL,
				snapshot_id VARCHAR(120) NOT NULL,
				operation_type VARCHAR(40) NOT NULL,
				operation_status VARCHAR(30) NOT NULL,
				requested_by VARCHAR(120) NOT NULL,
				reason VARCHAR(500) NOT NULL,
				idempotency_key VARCHAR(160) NOT NULL,
				created_at TIMESTAMP NOT NULL,
				UNIQUE (source_id, idempotency_key)
			)
			""");
		@SuppressWarnings("unchecked")
		ObjectProvider<Clock> clockProvider = mock(ObjectProvider.class);
		when(clockProvider.getIfAvailable(any())).thenReturn(
			Clock.fixed(Instant.parse("2026-07-15T00:00:00Z"), ZoneOffset.UTC)
		);
		service = new DatapackSourceSnapshotCommandService(
			new JdbcDataSourceSnapshotRepository(dataSource),
			new DataSourceTransactionManager(dataSource),
			clockProvider,
			new ObjectMapper()
		);
	}

	@Test
	@DisplayName("최초 snapshot만 previous와 diff가 없는 root로 저장한다")
	void firstSnapshotCreatesRoot() {
		assertThat(service.createLockedSnapshot(command("source-a", "snapshot-a-1", null, null)))
			.isEqualTo("snapshot-a-1");

		assertThatThrownBy(() -> service.createLockedSnapshot(command("source-a", "snapshot-a-orphan", "missing", changedDiff())))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("SOURCE_LINEAGE_BROKEN");
	}

	@Test
	@DisplayName("두 번째 snapshot은 같은 source의 현재 head와 structured diff를 요구한다")
	void laterSnapshotRequiresExactSourceHeadAndDiff() {
		service.createLockedSnapshot(command("source-a", "snapshot-a-1", null, null));
		service.createLockedSnapshot(command("source-b", "snapshot-b-1", null, null));

		assertThatThrownBy(() -> service.createLockedSnapshot(command("source-a", "snapshot-a-null", null, null)))
			.hasMessageContaining("SOURCE_LINEAGE_BROKEN");
		assertThatThrownBy(() -> service.createLockedSnapshot(command("source-a", "snapshot-a-cross", "snapshot-b-1", changedDiff())))
			.hasMessageContaining("SOURCE_LINEAGE_BROKEN");

		assertThat(service.createLockedSnapshot(command("source-a", "snapshot-a-2", "snapshot-a-1", changedDiff())))
			.isEqualTo("snapshot-a-2");
		assertThatThrownBy(() -> service.createLockedSnapshot(command("source-a", "snapshot-a-fork", "snapshot-a-1", changedDiff())))
			.hasMessageContaining("SOURCE_LINEAGE_BROKEN");
	}

	@Test
	@DisplayName("실제 변경과 맞지 않는 NO_CHANGE diff는 거부한다")
	void noChangeDiffMustMatchSnapshotFields() {
		service.createLockedSnapshot(command("source-a", "snapshot-a-1", null, null));

		assertThatThrownBy(() -> service.createLockedSnapshot(command(
			"source-a",
			"snapshot-a-2",
			"snapshot-a-1",
			noChangeDiff()
		)))
			.isInstanceOf(IllegalArgumentException.class)
			.hasMessageContaining("SOURCE_DIFF_MISSING");
	}

	@Test
	@DisplayName("같은 idempotency key와 byte-equivalent snapshot은 head가 전진해도 재생한다")
	void sameCommandReplaysIdempotently() {
		var first = command("source-a", "snapshot-a-1", null, null);

		assertThat(service.createLockedSnapshot(first)).isEqualTo("snapshot-a-1");
		assertThat(service.createLockedSnapshot(first)).isEqualTo("snapshot-a-1");
	}

	private SourceSnapshotCommand command(
		String sourceId,
		String snapshotId,
		String previousSnapshotId,
		String diffSummaryJson
	) {
		boolean root = previousSnapshotId == null;
		return new SourceSnapshotCommand(
			snapshotId,
			sourceId,
			"provider",
			LocalDateTime.of(2026, 7, root ? 1 : 2, 0, 0),
			LocalDateTime.of(2026, 7, root ? 1 : 2, 0, 0),
			root ? 10 : 12,
			root ? 8 : 9,
			(root ? "a" : "d").repeat(64),
			"s3://bucket/%s.json".formatted(snapshotId),
			"b".repeat(64),
			"c".repeat(64),
			"PASS",
			"PASS",
			"SUCCESS",
			true,
			true,
			previousSnapshotId,
			root ? null : "CHANGED",
			diffSummaryJson,
			LocalDateTime.of(2026, 8, root ? 1 : 2, 0, 0),
			LocalDateTime.of(2026, 9, root ? 29 : 30, 0, 0),
			"2026-07-15",
			"e".repeat(64),
			"qa-role",
			"source governance fixture",
			"idempotency-" + snapshotId
		);
	}

	private String changedDiff() {
		return """
			{"status":"CHANGED","rawHashChanged":true,"schemaHashChanged":false,"requestHashChanged":false,"sourceUpdatedAtChanged":true,"rowDelta":2,"coverageDelta":1}
			""".trim();
	}

	private String noChangeDiff() {
		return """
			{"status":"NO_CHANGE","rawHashChanged":false,"schemaHashChanged":false,"requestHashChanged":false,"sourceUpdatedAtChanged":false,"rowDelta":0,"coverageDelta":0}
			""".trim();
	}
}
