package com.easysubway.realtime.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.Instant;
import java.time.ZoneId;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("dev/test realtime safety port")
class DevelopmentRealtimeSafetyPortsTest {

	@Test
	@DisplayName("provider별 quota 상태를 서로 격리한다")
	void isolatesQuotaByProvider() {
		DevelopmentRealtimeSafetyPorts ports = new DevelopmentRealtimeSafetyPorts();
		Instant now = Instant.parse("2026-07-13T01:00:00Z");
		ZoneId providerZone = ZoneId.of("Asia/Seoul");

		assertThat(ports.tryAcquire("seoul-topis", now, providerZone, 1, 1)).isTrue();
		assertThat(ports.tryAcquire("seoul-topis", now, providerZone, 1, 1)).isFalse();
		assertThat(ports.tryAcquire("other-provider", now, providerZone, 1, 1)).isTrue();
	}
}
