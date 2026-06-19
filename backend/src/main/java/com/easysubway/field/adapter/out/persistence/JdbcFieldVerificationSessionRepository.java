package com.easysubway.field.adapter.out.persistence;

import com.easysubway.field.application.port.out.FieldVerificationSessionRepository;
import com.easysubway.field.domain.FieldVerificationItem;
import com.easysubway.field.domain.FieldVerificationItemType;
import com.easysubway.field.domain.FieldVerificationSession;
import com.easysubway.field.domain.FieldVerificationStatus;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;
import java.util.Optional;
import javax.sql.DataSource;
import org.springframework.context.annotation.Profile;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
@Profile("prod")
public class JdbcFieldVerificationSessionRepository implements FieldVerificationSessionRepository {

	private final JdbcTemplate jdbcTemplate;

	public JdbcFieldVerificationSessionRepository(DataSource dataSource) {
		this(new JdbcTemplate(dataSource));
	}

	JdbcFieldVerificationSessionRepository(JdbcTemplate jdbcTemplate) {
		this.jdbcTemplate = jdbcTemplate;
	}

	@Override
	public List<FieldVerificationSession> listAll() {
		return jdbcTemplate.query(
			"""
				SELECT session_id,
					station_id,
					station_name,
					verified_at,
					verified_by,
					status,
					note
				FROM field_verification_sessions
				ORDER BY verified_at DESC, session_id ASC
				""",
			this::mapSession
		);
	}

	@Override
	public Optional<FieldVerificationSession> findByStationId(String stationId) {
		List<FieldVerificationSession> sessions = jdbcTemplate.query(
			"""
				SELECT session_id,
					station_id,
					station_name,
					verified_at,
					verified_by,
					status,
					note
				FROM field_verification_sessions
				WHERE station_id = ?
				ORDER BY verified_at DESC, session_id ASC
				LIMIT 1
				""",
			this::mapSession,
			stationId
		);
		return sessions.stream().findFirst();
	}

	@Override
	public void save(FieldVerificationSession session) {
		int updated = jdbcTemplate.update(
			"""
				UPDATE field_verification_sessions
				SET station_id = ?,
					station_name = ?,
					verified_at = ?,
					verified_by = ?,
					status = ?,
					note = ?
				WHERE session_id = ?
				""",
			session.stationId(),
			session.stationName(),
			session.verifiedAt(),
			session.verifiedBy(),
			session.status().name(),
			session.note(),
			session.id()
		);
		if (updated == 0) {
			jdbcTemplate.update(
				"""
					INSERT INTO field_verification_sessions (
						session_id,
						station_id,
						station_name,
						verified_at,
						verified_by,
						status,
						note
					)
					VALUES (?, ?, ?, ?, ?, ?, ?)
					""",
				session.id(),
				session.stationId(),
				session.stationName(),
				session.verifiedAt(),
				session.verifiedBy(),
				session.status().name(),
				session.note()
			);
		}
		session.items().forEach(item -> saveItem(session, item));
	}

	private void saveItem(FieldVerificationSession session, FieldVerificationItem item) {
		int updated = jdbcTemplate.update(
			"""
				UPDATE field_verification_items
				SET session_id = ?,
					item_type = ?,
					target_name = ?,
					status = ?,
					note = ?
				WHERE item_id = ?
				""",
			session.id(),
			item.type().name(),
			item.targetName(),
			item.status().name(),
			item.note(),
			item.id()
		);
		if (updated == 0) {
			jdbcTemplate.update(
				"""
					INSERT INTO field_verification_items (
						item_id,
						session_id,
						item_type,
						target_name,
						status,
						note
					)
					VALUES (?, ?, ?, ?, ?, ?)
					""",
				item.id(),
				session.id(),
				item.type().name(),
				item.targetName(),
				item.status().name(),
				item.note()
			);
		}
	}

	private FieldVerificationSession mapSession(ResultSet resultSet, int rowNumber) throws SQLException {
		String sessionId = resultSet.getString("session_id");
		return new FieldVerificationSession(
			sessionId,
			resultSet.getString("station_id"),
			resultSet.getString("station_name"),
			resultSet.getDate("verified_at").toLocalDate(),
			resultSet.getString("verified_by"),
			FieldVerificationStatus.valueOf(resultSet.getString("status")),
			resultSet.getString("note"),
			listItems(sessionId)
		);
	}

	private List<FieldVerificationItem> listItems(String sessionId) {
		return jdbcTemplate.query(
			"""
				SELECT item_id,
					item_type,
					target_name,
					status,
					note
				FROM field_verification_items
				WHERE session_id = ?
				ORDER BY item_type ASC, item_id ASC
				""",
			this::mapItem,
			sessionId
		);
	}

	private FieldVerificationItem mapItem(ResultSet resultSet, int rowNumber) throws SQLException {
		return new FieldVerificationItem(
			resultSet.getString("item_id"),
			FieldVerificationItemType.valueOf(resultSet.getString("item_type")),
			resultSet.getString("target_name"),
			FieldVerificationStatus.valueOf(resultSet.getString("status")),
			resultSet.getString("note")
		);
	}
}
