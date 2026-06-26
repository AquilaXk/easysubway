package com.easysubway.health.application.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.transit.adapter.out.persistence.UnavailableTransitMasterRepository;
import com.easysubway.transit.application.port.out.LoadTransitMasterPort;
import com.easysubway.health.domain.HealthStatus;
import javax.sql.DataSource;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("헬스체크 서비스")
class HealthCheckServiceTest {

	@Test
	@DisplayName("백엔드 상태와 서비스 이름, 기본 컴포넌트를 반환한다")
	void checkHealthReturnsBackendStatus() {
		HealthStatus status = new HealthCheckService((DataSource) null, (LoadTransitMasterPort) null).checkHealth();

		assertThat(status.status()).isEqualTo("UP");
		assertThat(status.service()).isEqualTo("easysubway-backend");
		assertThat(status.components())
			.extracting("name")
			.contains("application", "database", "masterData", "objectStorage", "batch", "pushOutbox", "backup");
	}

	@Test
	@DisplayName("읽기 전용 마스터 데이터는 health summary와 component 상태에 반영된다")
	void checkHealthReportsReadOnlyMasterData() {
		HealthStatus status = new HealthCheckService(null, new UnavailableTransitMasterRepository()).checkHealth();

		assertThat(status.status()).isEqualTo("READ_ONLY");
		assertThat(status.components())
			.filteredOn(component -> component.name().equals("masterData"))
			.singleElement()
			.satisfies(component -> {
				assertThat(component.status()).isEqualTo("READ_ONLY");
				assertThat(component.reason()).isEqualTo("마스터 데이터가 읽기 전용입니다.");
			});
	}
}
