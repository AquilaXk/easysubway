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
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

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
				FROM (
					SELECT session_id,
						station_id,
						station_name,
						verified_at,
						verified_by,
						status,
						note,
						ROW_NUMBER() OVER (
							PARTITION BY station_id
							ORDER BY verified_at DESC, session_id ASC
						) AS row_number
					FROM field_verification_sessions
				) ranked_sessions
				WHERE row_number = 1
				ORDER BY verified_at DESC, station_id DESC, session_id ASC
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
	@Transactional
	public void save(FieldVerificationSession session) {
		if (updateSession(session) == 0) {
			try {
				insertSession(session);
			} catch (DuplicateKeyException exception) {
				// 운영 다중 인스턴스가 같은 세션을 동시에 만들면 삽입 충돌 후 최신 값으로 수렴시킨다.
				updateSession(session);
			}
		}
		session.items().forEach(item -> saveItem(session, item));
	}

	private int updateSession(FieldVerificationSession session) {
		return jdbcTemplate.update(
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
	}

	private void insertSession(FieldVerificationSession session) {
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

	private void saveItem(FieldVerificationSession session, FieldVerificationItem item) {
		if (updateItem(session, item) == 0) {
			try {
				insertItem(session, item);
			} catch (DuplicateKeyException exception) {
				// 세션 항목도 같은 부트스트랩 race에서 삽입 충돌 후 최신 값으로 맞춘다.
				updateItem(session, item);
			}
		}
	}

	private int updateItem(FieldVerificationSession session, FieldVerificationItem item) {
		return jdbcTemplate.update(
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
	}

	private void insertItem(FieldVerificationSession session, FieldVerificationItem item) {
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
				ORDER BY CASE item_type
					WHEN 'EXIT' THEN 1
					WHEN 'ELEVATOR' THEN 2
					WHEN 'ESCALATOR' THEN 3
					WHEN 'RESTROOM' THEN 4
					WHEN 'PLATFORM_TRANSFER' THEN 5
					ELSE 99
				END ASC, item_id ASC
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
