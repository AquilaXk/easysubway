package com.easysubway.realtime.application;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.realtime.domain.RealtimeArrival;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("실시간 gateway cache와 fallback 정책")
class RealtimeGatewayServiceTest {

	@Test
	@DisplayName("같은 도착 요청은 cache TTL 안에서 provider 호출을 반복하지 않는다")
	void arrivalsUseCacheWithinTtl() {
		CountingProvider provider = new CountingProvider();
		RealtimeGatewayService service = new RealtimeGatewayService(
			provider,
			Clock.fixed(Instant.parse("2026-06-26T08:00:00Z"), ZoneOffset.UTC)
		);
		RealtimeQuery query = sangnoksuQuery();

		RealtimeArrivalResult first = service.arrivals(query);
		RealtimeArrivalResult second = service.arrivals(query);

		assertThat(first.status()).hasToString("FRESH");
		assertThat(second.status()).hasToString("FRESH");
		assertThat(provider.arrivalCalls).hasValue(1);
	}

	@Test
	@DisplayName("provider timeout은 stale cache가 있으면 stale 응답으로 낮춘다")
	void timeoutServesStaleCache() {
		MutableClock clock = new MutableClock(Instant.parse("2026-06-26T08:00:00Z"));
		CountingProvider provider = new CountingProvider();
		RealtimeGatewayService service = new RealtimeGatewayService(provider, clock);
		RealtimeQuery query = sangnoksuQuery();

		service.arrivals(query);
		clock.instant = Instant.parse("2026-06-26T08:00:30Z");
		provider.failureCode = "PROVIDER_TIMEOUT";
		RealtimeArrivalResult stale = service.arrivals(query);

		assertThat(stale.status()).hasToString("STALE");
		assertThat(stale.fallbackCode()).isEqualTo("STALE_CACHE");
		assertThat(stale.arrivals()).hasSize(1);
	}

	@Test
	@DisplayName("quota 초과는 circuit을 열고 다음 요청에서 provider를 호출하지 않는다")
	void quotaExhaustionOpensCircuit() {
		MutableClock clock = new MutableClock(Instant.parse("2026-06-26T08:00:00Z"));
		CountingProvider provider = new CountingProvider();
		RealtimeGatewayService service = new RealtimeGatewayService(provider, clock);
		RealtimeQuery query = sangnoksuQuery();
		provider.failureCode = "PROVIDER_QUOTA_EXCEEDED";

		RealtimeArrivalResult first = service.arrivals(query);
		RealtimeArrivalResult second = service.arrivals(query);

		assertThat(first.status()).hasToString("UNAVAILABLE");
		assertThat(second.status()).hasToString("UNAVAILABLE");
		assertThat(second.fallbackCode()).isEqualTo("PROVIDER_QUOTA_EXCEEDED");
		assertThat(provider.arrivalCalls).hasValue(1);
	}

	@Test
	@DisplayName("지원 범위 밖 역은 provider를 호출하지 않고 unsupported로 끝난다")
	void unsupportedSkipsProviderCall() {
		CountingProvider provider = new CountingProvider();
		RealtimeGatewayService service = new RealtimeGatewayService(
			provider,
			Clock.fixed(Instant.parse("2026-06-26T08:00:00Z"), ZoneOffset.UTC)
		);

		RealtimeArrivalResult result = service.arrivals(new RealtimeQuery(
			"station-outside",
			"other",
			null,
			"외부역",
			null
		));

		assertThat(result.status()).hasToString("UNSUPPORTED");
		assertThat(result.fallbackCode()).isEqualTo("UNSUPPORTED_REGION");
		assertThat(provider.arrivalCalls).hasValue(0);
	}

	@Test
	@DisplayName("TOPIS provider는 backend service key가 없으면 fixture로 안전하게 동작한다")
	void topisProviderUsesFixtureWhenBackendServiceKeyIsNotConfigured() {
		TopisRealtimeProvider provider = new TopisRealtimeProvider(
			"",
			new ObjectMapper(),
			java.net.http.HttpClient.newHttpClient(),
			new FixtureRealtimeProvider()
		);

		List<RealtimeArrival> arrivals = provider.arrivals(sangnoksuQuery());

		assertThat(arrivals).hasSize(1);
		assertThat(arrivals.get(0).stationName()).isEqualTo("상록수");
		assertThat(arrivals.get(0).message()).isEqualTo("3분 후");
	}

	private RealtimeQuery sangnoksuQuery() {
		return new RealtimeQuery("station-sangnoksu", "4", "1004", "상록수", null);
	}

	private static final class CountingProvider implements RealtimeProvider {
		private final AtomicInteger arrivalCalls = new AtomicInteger();
		private String failureCode;

		@Override
		public List<RealtimeArrival> arrivals(RealtimeQuery query) {
			arrivalCalls.incrementAndGet();
			if (failureCode != null) {
				throw new RealtimeProviderException(failureCode);
			}
			return List.of(new RealtimeArrival(
				"4",
				"상록수",
				"당고개",
				"상행",
				"4123",
				180,
				"3분 후",
				"전역 출발",
				"2026-06-26T08:00:00Z"
			));
		}
	}

	private static final class MutableClock extends Clock {
		private Instant instant;

		private MutableClock(Instant instant) {
			this.instant = instant;
		}

		@Override
		public ZoneOffset getZone() {
			return ZoneOffset.UTC;
		}

		@Override
		public Clock withZone(java.time.ZoneId zone) {
			return this;
		}

		@Override
		public Instant instant() {
			return instant;
		}
	}
}
