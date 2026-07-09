package com.easysubway.ads.adapter.out.persistence;

import com.easysubway.ads.application.port.out.AdRepository;
import com.easysubway.ads.domain.AdCreative;
import com.easysubway.ads.domain.AdEventType;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Optional;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

@Repository
class JdbcAdRepository implements AdRepository {

	private static final RowMapper<AdCreative> CREATIVE_ROW_MAPPER = JdbcAdRepository::mapCreative;

	private final JdbcTemplate jdbcTemplate;

	JdbcAdRepository(JdbcTemplate jdbcTemplate) {
		this.jdbcTemplate = jdbcTemplate;
	}

	@Override
	public Optional<AdCreative> findActive(String placementId, LocalDateTime now) {
		try {
			return Optional.ofNullable(jdbcTemplate.queryForObject("""
				SELECT c.id, c.placement_id, c.image_url, c.landing_url, c.advertiser_name,
				       c.alt_text, c.starts_at, c.ends_at
				FROM ad_creatives c
				JOIN ad_placements p ON p.id = c.placement_id
				WHERE c.placement_id = ?
				  AND p.enabled = TRUE
				  AND c.enabled = TRUE
				  AND c.starts_at <= ?
				  AND (c.ends_at IS NULL OR c.ends_at > ?)
				ORDER BY c.starts_at DESC, c.id
				LIMIT 1
				""", CREATIVE_ROW_MAPPER, placementId, now, now));
		} catch (EmptyResultDataAccessException exception) {
			return Optional.empty();
		}
	}

	@Override
	@Transactional
	public void incrementEvent(String placementId, String creativeId, AdEventType eventType, LocalDate eventDate) {
		int updated = jdbcTemplate.update("""
			UPDATE ad_event_daily
			SET event_count = event_count + 1
			WHERE event_date = ? AND placement_id = ? AND creative_id = ? AND event_type = ?
			""", eventDate, placementId, creativeId, eventType.name());
		if (updated > 0) {
			return;
		}
		try {
			jdbcTemplate.update("""
				INSERT INTO ad_event_daily (event_date, placement_id, creative_id, event_type, event_count)
				VALUES (?, ?, ?, ?, 1)
				""", eventDate, placementId, creativeId, eventType.name());
		} catch (DuplicateKeyException exception) {
			jdbcTemplate.update("""
				UPDATE ad_event_daily
				SET event_count = event_count + 1
				WHERE event_date = ? AND placement_id = ? AND creative_id = ? AND event_type = ?
				""", eventDate, placementId, creativeId, eventType.name());
		} catch (DataIntegrityViolationException exception) {
			// Unknown or mismatched ad ids are ignored so the public event endpoint stays anonymous and non-fatal.
		}
	}

	private static AdCreative mapCreative(ResultSet resultSet, int rowNumber) throws SQLException {
		return new AdCreative(
			resultSet.getString("id"),
			resultSet.getString("placement_id"),
			resultSet.getString("image_url"),
			resultSet.getString("landing_url"),
			resultSet.getString("advertiser_name"),
			resultSet.getString("alt_text"),
			resultSet.getTimestamp("starts_at").toLocalDateTime(),
			resultSet.getTimestamp("ends_at") == null ? null : resultSet.getTimestamp("ends_at").toLocalDateTime());
	}
}
