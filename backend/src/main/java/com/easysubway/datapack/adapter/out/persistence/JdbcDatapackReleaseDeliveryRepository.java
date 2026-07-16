package com.easysubway.datapack.adapter.out.persistence;

import com.easysubway.datapack.domain.DatapackReleaseDelivery;
import com.easysubway.datapack.domain.DatapackReleaseDelivery.State;
import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;

@Repository
public class JdbcDatapackReleaseDeliveryRepository {
	private static final RowMapper<DatapackReleaseDelivery> ROW_MAPPER = (rs, rowNum) ->
		new DatapackReleaseDelivery(
			rs.getString("idempotency_key"), rs.getString("release_request_id"),
			rs.getLong("release_sequence"), rs.getString("manifest_sha256"),
			rs.getString("channel"), rs.getString("candidate_id"),
			rs.getString("payload_sha256"), rs.getString("signature_sha256"),
			State.valueOf(rs.getString("state")), rs.getInt("attempts"),
			ldt(rs.getTimestamp("next_attempt_at")), ldt(rs.getTimestamp("reconcile_deadline")),
			ldt(rs.getTimestamp("dead_letter_deadline")), rs.getString("http_class"),
			rs.getString("sanitized_detail"), ldt(rs.getTimestamp("claimed_at")),
			rs.getString("claim_owner"), ldt(rs.getTimestamp("created_at")),
			ldt(rs.getTimestamp("updated_at")));

	private final JdbcTemplate jdbcTemplate;

	public JdbcDatapackReleaseDeliveryRepository(JdbcTemplate jdbcTemplate) {
		this.jdbcTemplate = jdbcTemplate;
	}

	public DatapackReleaseDelivery upsertSameDelivery(DatapackReleaseDelivery delivery) {
		try {
			insert(delivery);
			return delivery;
		} catch (DuplicateKeyException duplicate) {
			return findByIdempotencyKey(delivery.idempotencyKey()).orElseThrow(() -> duplicate);
		}
	}

	public Optional<DatapackReleaseDelivery> findByIdempotencyKey(String idempotencyKey) {
		try {
			return Optional.ofNullable(jdbcTemplate.queryForObject(
				"SELECT * FROM datapack_release_deliveries WHERE idempotency_key=?",
				ROW_MAPPER, idempotencyKey));
		} catch (EmptyResultDataAccessException ignored) {
			return Optional.empty();
		}
	}

	public List<DatapackReleaseDelivery> claimDue(LocalDateTime now, String owner) {
		var keys = jdbcTemplate.queryForList("""
			SELECT idempotency_key FROM datapack_release_deliveries
			WHERE state IN ('PENDING', 'RETRY_SCHEDULED', 'RECONCILIATION_REQUIRED')
			  AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
			  AND claimed_at IS NULL
			ORDER BY created_at, idempotency_key
			""", String.class, ts(now));
		var claimed = new ArrayList<DatapackReleaseDelivery>();
		for (String key : keys) {
			int changed = jdbcTemplate.update("""
				UPDATE datapack_release_deliveries SET claimed_at=?, claim_owner=?, updated_at=?
				WHERE idempotency_key=? AND claimed_at IS NULL
				  AND state IN ('PENDING', 'RETRY_SCHEDULED', 'RECONCILIATION_REQUIRED')
				""", ts(now), owner, ts(now), key);
			if (changed == 1) findByIdempotencyKey(key).ifPresent(claimed::add);
		}
		return claimed;
	}

	public void mark(String idempotencyKey, State state, int attempts, LocalDateTime nextAttemptAt,
		String httpClass, String detail, LocalDateTime now) {
		jdbcTemplate.update("""
			UPDATE datapack_release_deliveries
			SET state=?, attempts=?, next_attempt_at=?, http_class=?, sanitized_detail=?,
			    claimed_at=NULL, claim_owner=NULL, updated_at=?
			WHERE idempotency_key=?
			""", state.name(), attempts, ts(nextAttemptAt), httpClass, detail, ts(now), idempotencyKey);
	}

	public List<DatapackReleaseDelivery> findRecent(int limit) {
		return jdbcTemplate.query("""
			SELECT * FROM datapack_release_deliveries
			ORDER BY created_at DESC, idempotency_key DESC LIMIT ?
			""", ROW_MAPPER, limit);
	}

	private void insert(DatapackReleaseDelivery d) {
		jdbcTemplate.update("""
			INSERT INTO datapack_release_deliveries (
			 idempotency_key, release_request_id, release_sequence, manifest_sha256, channel,
			 candidate_id, payload_sha256, signature_sha256, state, attempts, next_attempt_at,
			 reconcile_deadline, dead_letter_deadline, http_class, sanitized_detail,
			 claimed_at, claim_owner, created_at, updated_at)
			VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
			""", d.idempotencyKey(), d.releaseRequestId(), d.releaseSequence(), d.manifestSha256(),
			d.channel(), d.candidateId(), d.payloadSha256(), d.signatureSha256(), d.state().name(),
			d.attempts(), ts(d.nextAttemptAt()), ts(d.reconcileDeadline()), ts(d.deadLetterDeadline()),
			d.httpClass(), d.sanitizedDetail(), ts(d.claimedAt()), d.claimOwner(),
			ts(d.createdAt()), ts(d.updatedAt()));
	}

	private static Timestamp ts(LocalDateTime value) {
		return value == null ? null : Timestamp.valueOf(value);
	}

	private static LocalDateTime ldt(Timestamp value) {
		return value == null ? null : value.toLocalDateTime();
	}
}
