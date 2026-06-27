package com.easysubway.transit.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.transit.application.port.out.MasterDataCapabilityStatus;
import com.easysubway.transit.domain.AccessibilityFacility;
import com.easysubway.transit.domain.AccessibilityFacilityStatus;
import com.easysubway.transit.domain.AccessibilityFacilityType;
import com.easysubway.transit.domain.DataConfidenceLevel;
import com.easysubway.transit.domain.DataSourceType;
import com.easysubway.transit.domain.RouteEdge;
import com.easysubway.transit.domain.RouteEdgeType;
import com.easysubway.transit.domain.RouteNode;
import com.easysubway.transit.domain.RouteNodeType;
import com.easysubway.transit.domain.SimplifiedStationLayoutStatus;
import com.easysubway.transit.domain.StationLayoutSource;
import com.easysubway.transit.domain.StationLayoutSourceType;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.math.BigDecimal;
import java.time.LocalDate;
import javax.sql.DataSource;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseBuilder;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

@DisplayName("JDBC 도시철도 마스터 override 저장소")
class JdbcTransitMasterOverrideRepositoryTest {

	@Test
	@DisplayName("override table readiness가 writable capability를 결정한다")
	void readinessControlsWritableCapability() {
		var ready = new JdbcTransitMasterOverrideRepository(overrideDataSource(), objectMapper()).masterDataCapability();
		var unready = new JdbcTransitMasterOverrideRepository(emptyDataSource(), objectMapper()).masterDataCapability();

		assertThat(ready.status()).isEqualTo(MasterDataCapabilityStatus.UP);
		assertThat(ready.writable()).isTrue();
		assertThat(unready.status()).isEqualTo(MasterDataCapabilityStatus.READ_ONLY);
		assertThat(unready.writable()).isFalse();
	}

	@Test
	@DisplayName("시설 상태와 metadata override는 저장 후 새 repository에서도 effective model로 읽힌다")
	void facilityOverridesPersistAndMergeWithCatalog() {
		DataSource dataSource = overrideDataSource();
		var repository = new JdbcTransitMasterOverrideRepository(dataSource, objectMapper());

		repository.saveFacilityStatus(
			"facility-sangnoksu-elevator-1",
			AccessibilityFacilityStatus.BROKEN,
			LocalDate.of(2026, 6, 27)
		);
		repository.saveAccessibilityFacility(new AccessibilityFacility(
			"facility-ops-new",
			"station-sangnoksu",
			"exit-sangnoksu-1",
			AccessibilityFacilityType.RAMP,
			"임시 경사로",
			"지상",
			"대합실",
			new BigDecimal("37.302500"),
			new BigDecimal("126.866300"),
			"운영자가 추가한 임시 이동 동선입니다.",
			AccessibilityFacilityStatus.ADMIN_VERIFIED,
			DataConfidenceLevel.MEDIUM,
			DataSourceType.ADMIN_VERIFIED,
			LocalDate.of(2026, 6, 27)
		));

		var reloaded = new JdbcTransitMasterOverrideRepository(dataSource, objectMapper());
		assertThat(reloaded.loadAccessibilityFacility("facility-sangnoksu-elevator-1")).hasValueSatisfying(facility -> {
			assertThat(facility.status()).isEqualTo(AccessibilityFacilityStatus.BROKEN);
			assertThat(facility.dataSourceType()).isEqualTo(DataSourceType.ADMIN_VERIFIED);
			assertThat(facility.lastUpdatedAt()).isEqualTo(LocalDate.of(2026, 6, 27));
		});
		assertThat(reloaded.loadAccessibilityFacility("facility-ops-new")).hasValueSatisfying(facility ->
			assertThat(facility.name()).isEqualTo("임시 경사로")
		);
		assertThat(reloaded.listMasterDataOverrideAudits(
			JdbcTransitMasterOverrideRepository.FACILITY,
			"facility-sangnoksu-elevator-1"
		)).hasSize(1);
	}

	@Test
	@DisplayName("구조도 source/status, route node/edge override를 저장하고 재조회한다")
	void layoutAndRouteOverridesPersist() {
		DataSource dataSource = overrideDataSource();
		var repository = new JdbcTransitMasterOverrideRepository(dataSource, objectMapper());

		repository.saveStationLayoutSource(new StationLayoutSource(
			"layout-source-sangnoksu-station-map",
			"station-sangnoksu",
			StationLayoutSourceType.FIELD_SURVEY,
			"현장 검수 구조도",
			"https://ops.easysubway.example/layout",
			"운영 검수 자료",
			true,
			false,
			LocalDate.of(2026, 6, 20),
			LocalDate.of(2026, 6, 27)
		));
		repository.saveSimplifiedStationLayoutStatus(
			"layout-sangnoksu-draft",
			SimplifiedStationLayoutStatus.PUBLISHED,
			"layout-admin",
			LocalDate.of(2026, 6, 27)
		);
		repository.saveRouteNode(new RouteNode(
			"node-sangnoksu-elevator-1",
			"station-sangnoksu",
			RouteNodeType.ELEVATOR,
			"1번 출구 엘리베이터",
			"B1",
			new BigDecimal("37.302421"),
			new BigDecimal("126.866221"),
			"facility-sangnoksu-elevator-1",
			"layout-sangnoksu-draft",
			140,
			260,
			"운영 보정 엘리베이터",
			"출입구 앞 점자블록 확인"
		));
		repository.saveRouteEdge(new RouteEdge(
			"edge-sangnoksu-elevator-to-faregate",
			"station-sangnoksu",
			"node-sangnoksu-elevator-1",
			"node-sangnoksu-faregate",
			RouteEdgeType.WALK,
			30,
			80,
			false,
			true,
			false,
			1,
			3,
			88,
			true
		));

		var reloaded = new JdbcTransitMasterOverrideRepository(dataSource, objectMapper());
		assertThat(reloaded.loadStationLayoutSources()).anySatisfy(source -> {
			assertThat(source.id()).isEqualTo("layout-source-sangnoksu-station-map");
			assertThat(source.sourceType()).isEqualTo(StationLayoutSourceType.FIELD_SURVEY);
			assertThat(source.reviewedAt()).isEqualTo(LocalDate.of(2026, 6, 27));
		});
		assertThat(reloaded.loadSimplifiedStationLayouts()).anySatisfy(layout -> {
			assertThat(layout.id()).isEqualTo("layout-sangnoksu-draft");
			assertThat(layout.status()).isEqualTo(SimplifiedStationLayoutStatus.PUBLISHED);
			assertThat(layout.version()).isEqualTo(2);
		});
		assertThat(reloaded.loadRouteNodes()).anySatisfy(node -> {
			assertThat(node.id()).isEqualTo("node-sangnoksu-elevator-1");
			assertThat(node.displayX()).isEqualTo(140);
			assertThat(node.displayLabel()).isEqualTo("운영 보정 엘리베이터");
		});
		assertThat(reloaded.loadRouteEdges()).anySatisfy(edge -> {
			assertThat(edge.id()).isEqualTo("edge-sangnoksu-elevator-to-faregate");
			assertThat(edge.distanceMeters()).isEqualTo(30);
			assertThat(edge.widthLevel()).isEqualTo(3);
		});
	}

	@Test
	@DisplayName("rollback은 마지막 override를 audit으로 남기고 catalog 원본으로 되돌린다")
	void rollbackRestoresCatalogValueAndWritesAudit() {
		DataSource dataSource = overrideDataSource();
		var repository = new JdbcTransitMasterOverrideRepository(dataSource, objectMapper());

		repository.saveFacilityStatus(
			"facility-sangnoksu-elevator-1",
			AccessibilityFacilityStatus.BROKEN,
			LocalDate.of(2026, 6, 27)
		);
		repository.rollbackMasterDataOverride(
			JdbcTransitMasterOverrideRepository.FACILITY,
			"facility-sangnoksu-elevator-1",
			"admin-user"
		);

		assertThat(repository.loadAccessibilityFacility("facility-sangnoksu-elevator-1")).hasValueSatisfying(facility ->
			assertThat(facility.status()).isEqualTo(AccessibilityFacilityStatus.NORMAL)
		);
		assertThat(repository.listMasterDataOverrideAudits(
			JdbcTransitMasterOverrideRepository.FACILITY,
			"facility-sangnoksu-elevator-1"
		))
			.extracting(com.easysubway.transit.application.port.out.TransitMasterOverrideAudit::action)
			.containsExactly("ROLLBACK", "UPSERT");
	}

	private DataSource overrideDataSource() {
		var dataSource = emptyDataSource();
		new ResourceDatabasePopulator(new ClassPathResource("db/migration/h2/V14__transit_master_overrides.sql"))
			.execute(dataSource);
		return dataSource;
	}

	private DataSource emptyDataSource() {
		return new EmbeddedDatabaseBuilder()
			.setType(EmbeddedDatabaseType.H2)
			.generateUniqueName(true)
			.build();
	}

	private ObjectMapper objectMapper() {
		return new ObjectMapper().findAndRegisterModules();
	}
}
