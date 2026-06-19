package com.easysubway.field.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.field.domain.FieldVerificationItem;
import com.easysubway.field.domain.FieldVerificationItemType;
import com.easysubway.field.domain.FieldVerificationSession;
import com.easysubway.field.domain.FieldVerificationStatus;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.DriverManagerDataSource;

@DisplayName("JDBC 현장 검증 세션 저장소")
class JdbcFieldVerificationSessionRepositoryTest {

	private JdbcFieldVerificationSessionRepository repository;

	@BeforeEach
	void setUp() {
		var dataSource = new DriverManagerDataSource(
			"jdbc:h2:mem:field-verification-session;MODE=PostgreSQL;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
			"sa",
			""
		);
		var jdbcTemplate = new JdbcTemplate(dataSource);
		jdbcTemplate.execute("DROP TABLE IF EXISTS field_verification_items");
		jdbcTemplate.execute("DROP TABLE IF EXISTS field_verification_sessions");
		jdbcTemplate.execute("""
			CREATE TABLE field_verification_sessions (
				session_id VARCHAR(120) PRIMARY KEY,
				station_id VARCHAR(120) NOT NULL,
				station_name VARCHAR(120) NOT NULL,
				verified_at DATE NOT NULL,
				verified_by VARCHAR(120) NOT NULL,
				status VARCHAR(40) NOT NULL,
				note VARCHAR(1000)
			)
			""");
		jdbcTemplate.execute("""
			CREATE TABLE field_verification_items (
				item_id VARCHAR(120) PRIMARY KEY,
				session_id VARCHAR(120) NOT NULL,
				item_type VARCHAR(40) NOT NULL,
				target_name VARCHAR(200) NOT NULL,
				status VARCHAR(40) NOT NULL,
				note VARCHAR(1000)
			)
			""");
		repository = new JdbcFieldVerificationSessionRepository(jdbcTemplate);
	}

	@Test
	@DisplayName("세션과 항목을 저장하고 역 기준으로 조회한다")
	void saveSessionAndFindByStationId() {
		repository.save(session("field-verification-sadang-2026-06", "station-sadang", FieldVerificationStatus.PLANNED));

		var found = repository.findByStationId("station-sadang");

		assertThat(found).isPresent();
		assertThat(found.get()).satisfies(session -> {
			assertThat(session.id()).isEqualTo("field-verification-sadang-2026-06");
			assertThat(session.stationName()).isEqualTo("사당역");
			assertThat(session.verifiedAt()).isEqualTo(LocalDate.of(2026, 6, 19));
			assertThat(session.status()).isEqualTo(FieldVerificationStatus.PLANNED);
			assertThat(session.items())
				.extracting(FieldVerificationItem::id)
				.containsExactly("field-verification-sadang-elevator", "field-verification-sadang-restroom");
		});
	}

	@Test
	@DisplayName("세션과 항목 상태를 다시 저장하면 기존 값을 갱신한다")
	void saveUpdatesExistingSessionAndItems() {
		repository.save(session("field-verification-sadang-2026-06", "station-sadang", FieldVerificationStatus.PLANNED));
		repository.save(new FieldVerificationSession(
			"field-verification-sadang-2026-06",
			"station-sadang",
			"사당역",
			LocalDate.of(2026, 6, 19),
			"field-team",
			FieldVerificationStatus.NEEDS_RECHECK,
			"주요 환승역 현장 검증 확대 기준선",
			List.of(
				new FieldVerificationItem(
					"field-verification-sadang-elevator",
					FieldVerificationItemType.ELEVATOR,
					"환승 구간 엘리베이터 위치와 운행 상태",
					FieldVerificationStatus.NEEDS_RECHECK,
					"엘리베이터 운행 중지 안내문 확인 필요"
				),
				new FieldVerificationItem(
					"field-verification-sadang-restroom",
					FieldVerificationItemType.RESTROOM,
					"일반/장애인 화장실 위치",
					FieldVerificationStatus.PLANNED,
					null
				)
			)
		));

		var found = repository.findByStationId("station-sadang").orElseThrow();

		assertThat(found.status()).isEqualTo(FieldVerificationStatus.NEEDS_RECHECK);
		assertThat(found.items())
			.filteredOn(item -> item.id().equals("field-verification-sadang-elevator"))
			.singleElement()
			.satisfies(item -> {
				assertThat(item.status()).isEqualTo(FieldVerificationStatus.NEEDS_RECHECK);
				assertThat(item.note()).isEqualTo("엘리베이터 운행 중지 안내문 확인 필요");
			});
	}

	@Test
	@DisplayName("세션 목록은 검증일 최신순과 세션 식별자순으로 조회한다")
	void listAllOrdersByVerificationDateAndSessionId() {
		repository.save(session("field-verification-sadang-2026-06", "station-sadang", FieldVerificationStatus.PLANNED));
		repository.save(session("field-verification-sangnoksu-2026-06", "station-sangnoksu", FieldVerificationStatus.IN_PROGRESS));

		var sessions = repository.listAll();

		assertThat(sessions)
			.extracting(FieldVerificationSession::stationId)
			.containsExactly("station-sadang", "station-sangnoksu");
	}

	private FieldVerificationSession session(String sessionId, String stationId, FieldVerificationStatus status) {
		return new FieldVerificationSession(
			sessionId,
			stationId,
			stationId.equals("station-sadang") ? "사당역" : "상록수역",
			LocalDate.of(2026, 6, 19),
			"field-team",
			status,
			stationId.equals("station-sadang") ? "주요 환승역 현장 검증 확대 기준선" : "첫 현장 검증 지역 기준선",
			List.of(
				new FieldVerificationItem(
					"field-verification-" + stationId.replace("station-", "") + "-elevator",
					FieldVerificationItemType.ELEVATOR,
					stationId.equals("station-sadang") ? "환승 구간 엘리베이터 위치와 운행 상태" : "엘리베이터 위치와 운행 상태",
					status,
					null
				),
				new FieldVerificationItem(
					"field-verification-" + stationId.replace("station-", "") + "-restroom",
					FieldVerificationItemType.RESTROOM,
					"일반/장애인 화장실 위치",
					FieldVerificationStatus.PLANNED,
					null
				)
			)
		);
	}
}
