package com.easysubway.realtime.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.easysubway.realtime.domain.RealtimeArrival;
import com.easysubway.realtime.domain.RealtimeTrainPosition;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
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
	@DisplayName("같은 도착 요청의 동시 cache miss는 provider 호출을 공유한다")
	void concurrentArrivalMissesShareProviderCall() throws Exception {
		BlockingProvider provider = new BlockingProvider();
		RealtimeGatewayService service = new RealtimeGatewayService(
			provider,
			Clock.fixed(Instant.parse("2026-06-26T08:00:00Z"), ZoneOffset.UTC)
		);
		ExecutorService executor = Executors.newFixedThreadPool(2);
		try {
			CompletableFuture<RealtimeArrivalResult> first = CompletableFuture.supplyAsync(
				() -> service.arrivals(sangnoksuQuery()),
				executor
			);
			assertThat(provider.arrivalEntered.await(1, TimeUnit.SECONDS)).isTrue();
			CompletableFuture<RealtimeArrivalResult> second = CompletableFuture.supplyAsync(
				() -> service.arrivals(sangnoksuQuery()),
				executor
			);
			Thread.sleep(100);

			assertThat(provider.arrivalCalls).hasValue(1);
			provider.releaseArrivals.countDown();

			assertThat(first.get(1, TimeUnit.SECONDS).status()).hasToString("FRESH");
			assertThat(second.get(1, TimeUnit.SECONDS).status()).hasToString("FRESH");
			assertThat(provider.arrivalCalls).hasValue(1);
		} finally {
			executor.shutdownNow();
		}
	}

	@Test
	@DisplayName("같은 열차 위치 요청의 동시 cache miss는 provider 호출을 공유한다")
	void concurrentTrainPositionMissesShareProviderCall() throws Exception {
		BlockingProvider provider = new BlockingProvider();
		RealtimeGatewayService service = new RealtimeGatewayService(
			provider,
			Clock.fixed(Instant.parse("2026-06-26T08:00:00Z"), ZoneOffset.UTC)
		);
		ExecutorService executor = Executors.newFixedThreadPool(2);
		try {
			CompletableFuture<RealtimeTrainPositionResult> first = CompletableFuture.supplyAsync(
				() -> service.trainPositions(line4Query()),
				executor
			);
			assertThat(provider.trainPositionEntered.await(1, TimeUnit.SECONDS)).isTrue();
			CompletableFuture<RealtimeTrainPositionResult> second = CompletableFuture.supplyAsync(
				() -> service.trainPositions(line4Query()),
				executor
			);
			Thread.sleep(100);

			assertThat(provider.trainPositionCalls).hasValue(1);
			provider.releaseTrainPositions.countDown();

			assertThat(first.get(1, TimeUnit.SECONDS).status()).hasToString("FRESH");
			assertThat(second.get(1, TimeUnit.SECONDS).status()).hasToString("FRESH");
			assertThat(provider.trainPositionCalls).hasValue(1);
		} finally {
			executor.shutdownNow();
		}
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
	@DisplayName("열차 위치 quota 초과도 circuit을 열고 다음 요청에서 provider를 호출하지 않는다")
	void trainPositionQuotaExhaustionOpensCircuit() {
		MutableClock clock = new MutableClock(Instant.parse("2026-06-26T08:00:00Z"));
		CountingProvider provider = new CountingProvider();
		RealtimeGatewayService service = new RealtimeGatewayService(provider, clock);
		RealtimeQuery query = line4Query();
		provider.failureCode = "PROVIDER_QUOTA_EXCEEDED";

		RealtimeTrainPositionResult first = service.trainPositions(query);
		RealtimeTrainPositionResult second = service.trainPositions(query);

		assertThat(first.status()).hasToString("UNAVAILABLE");
		assertThat(second.status()).hasToString("UNAVAILABLE");
		assertThat(second.fallbackCode()).isEqualTo("PROVIDER_QUOTA_EXCEEDED");
		assertThat(provider.trainPositionCalls).hasValue(1);
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
	@DisplayName("불일치한 역 query 조합은 provider를 호출하지 않고 unsupported로 끝난다")
	void mismatchedArrivalQuerySkipsProviderCall() {
		CountingProvider provider = new CountingProvider();
		RealtimeGatewayService service = new RealtimeGatewayService(
			provider,
			Clock.fixed(Instant.parse("2026-06-26T08:00:00Z"), ZoneOffset.UTC)
		);

		RealtimeArrivalResult result = service.arrivals(new RealtimeQuery(
			"station-sangnoksu",
			"4",
			"1004",
			"서울",
			null
		));

		assertThat(result.status()).hasToString("UNSUPPORTED");
		assertThat(result.fallbackCode()).isEqualTo("UNSUPPORTED_REGION");
		assertThat(provider.arrivalCalls).hasValue(0);
	}

	@Test
	@DisplayName("불일치한 열차 위치 query 조합은 provider를 호출하지 않고 unsupported로 끝난다")
	void mismatchedTrainPositionQuerySkipsProviderCall() {
		CountingProvider provider = new CountingProvider();
		RealtimeGatewayService service = new RealtimeGatewayService(
			provider,
			Clock.fixed(Instant.parse("2026-06-26T08:00:00Z"), ZoneOffset.UTC)
		);

		RealtimeTrainPositionResult result = service.trainPositions(new RealtimeQuery(
			null,
			"4",
			"1004",
			null,
			"1호선"
		));

		assertThat(result.status()).hasToString("UNSUPPORTED");
		assertThat(result.fallbackCode()).isEqualTo("UNSUPPORTED_REGION");
		assertThat(provider.trainPositionCalls).hasValue(0);
	}

	@Test
	@DisplayName("provider empty 결과는 quota circuit을 열지 않는다")
	void emptyProviderResultDoesNotOpenQuotaCircuit() {
		CountingProvider provider = new CountingProvider();
		RealtimeGatewayService service = new RealtimeGatewayService(
			provider,
			Clock.fixed(Instant.parse("2026-06-26T08:00:00Z"), ZoneOffset.UTC)
		);
		provider.emptyArrivals = true;

		RealtimeArrivalResult empty = service.arrivals(sangnoksuQuery());
		provider.emptyArrivals = false;
		RealtimeArrivalResult fresh = service.arrivals(sangnoksuQuery());

		assertThat(empty.status()).hasToString("UNAVAILABLE");
		assertThat(empty.fallbackCode()).isEqualTo("EMPTY_PROVIDER_RESULT");
		assertThat(fresh.status()).hasToString("FRESH");
		assertThat(provider.arrivalCalls).hasValue(2);
	}

	@Test
	@DisplayName("TOPIS provider는 backend service key가 없으면 unavailable로 낮춘다")
	void topisProviderWithoutBackendServiceKeyIsUnavailableByDefault() {
		TopisRealtimeProvider provider = new TopisRealtimeProvider(
			"",
			new ObjectMapper(),
			java.net.http.HttpClient.newHttpClient(),
			new FixtureRealtimeProvider()
		);

		assertThatThrownBy(() -> provider.arrivals(sangnoksuQuery()))
			.isInstanceOf(RealtimeProviderException.class)
			.hasMessage("PROVIDER_UNAVAILABLE");
	}

	@Test
	@DisplayName("TOPIS provider timeout은 realtime contract 값과 일치한다")
	void topisProviderTimeoutMatchesContract() throws Exception {
		java.lang.reflect.Field timeoutField = TopisRealtimeProvider.class.getDeclaredField("REQUEST_TIMEOUT");
		timeoutField.setAccessible(true);

		assertThat(timeoutField.get(null)).isEqualTo(Duration.ofMillis(1500));
	}

	@Test
	@DisplayName("TOPIS provider timeout 예외는 realtime timeout fallback 코드로 변환한다")
	void topisProviderMapsHttpTimeoutToProviderTimeout() {
		TopisRealtimeProvider provider = new TopisRealtimeProvider(
			"backend-key",
			new ObjectMapper(),
			new TimeoutHttpClient(),
			new FixtureRealtimeProvider()
		);

		assertThatThrownBy(() -> provider.arrivals(sangnoksuQuery()))
			.isInstanceOf(RealtimeProviderException.class)
			.hasMessage("PROVIDER_TIMEOUT");
	}

	@Test
	@DisplayName("TOPIS provider fixture는 명시적으로 켠 테스트 경로에서만 동작한다")
	void topisProviderUsesFixtureOnlyWhenExplicitlyEnabled() {
		TopisRealtimeProvider provider = new TopisRealtimeProvider(
			"",
			new ObjectMapper(),
			java.net.http.HttpClient.newHttpClient(),
			new FixtureRealtimeProvider(),
			true
		);

		List<RealtimeArrival> arrivals = provider.arrivals(sangnoksuQuery());

		assertThat(arrivals).hasSize(1);
		assertThat(arrivals.get(0).stationName()).isEqualTo("상록수");
		assertThat(arrivals.get(0).message()).isEqualTo("3분 후");
	}

	@Test
	@DisplayName("TOPIS INFO-200 empty result는 quota exception으로 처리하지 않는다")
	void topisInfo200DoesNotOpenQuotaCircuit() throws Exception {
		ObjectMapper objectMapper = new ObjectMapper();
		TopisRealtimeProvider provider = new TopisRealtimeProvider(
			"backend-key",
			objectMapper,
			java.net.http.HttpClient.newHttpClient(),
			new FixtureRealtimeProvider()
		);

		provider.validateTopisStatus(objectMapper.readTree("""
			{
			  "errorMessage": {"code": "INFO-200", "message": "해당하는 데이터가 없습니다."}
			}
			"""));
	}

	@Test
	@DisplayName("TOPIS 도착 payload는 bstatnNm이 없으면 trainLineNm을 목적지 fallback으로 사용한다")
	void topisArrivalPayloadUsesTrainLineNameWhenDestinationNameIsMissing() throws Exception {
		ObjectMapper objectMapper = new ObjectMapper();
		TopisRealtimeProvider provider = new TopisRealtimeProvider(
			"backend-key",
			objectMapper,
			java.net.http.HttpClient.newHttpClient(),
			new FixtureRealtimeProvider()
		);

		List<RealtimeArrival> arrivals = provider.arrivalsFromPayload(
			objectMapper.readTree("""
				{
				  "errorMessage": {"code": "INFO-000"},
				  "realtimeArrivalList": [
				    {
				      "subwayId": "1004",
				      "statnNm": "상록수",
				      "trainLineNm": "오이도행 - 중앙방면",
				      "updnLine": "하행",
				      "btrainNo": "4001",
				      "barvlDt": "180",
				      "arvlMsg2": "3분 후"
				    }
				  ]
				}
				"""),
			sangnoksuQuery()
		);

		assertThat(arrivals).hasSize(1);
		assertThat(arrivals.get(0).destination()).isEqualTo("오이도행 - 중앙방면");
	}

	private RealtimeQuery sangnoksuQuery() {
		return new RealtimeQuery("station-sangnoksu", "4", "1004", "상록수", null);
	}

	private RealtimeQuery line4Query() {
		return new RealtimeQuery(null, "4", "1004", null, "4호선");
	}

	private static final class CountingProvider implements RealtimeProvider {
		private final AtomicInteger arrivalCalls = new AtomicInteger();
		private final AtomicInteger trainPositionCalls = new AtomicInteger();
		private String failureCode;
		private boolean emptyArrivals;

		@Override
		public List<RealtimeArrival> arrivals(RealtimeQuery query) {
			arrivalCalls.incrementAndGet();
			if (failureCode != null) {
				throw new RealtimeProviderException(failureCode);
			}
			if (emptyArrivals) {
				return List.of();
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

		@Override
		public List<RealtimeTrainPosition> trainPositions(RealtimeQuery query) {
			trainPositionCalls.incrementAndGet();
			if (failureCode != null) {
				throw new RealtimeProviderException(failureCode);
			}
			return List.of(new RealtimeTrainPosition(
				"4",
				"상록수",
				"4123",
				"운행중",
				"상행",
				"당고개",
				"2026-06-26T08:00:00Z"
			));
		}
	}

	private static final class BlockingProvider implements RealtimeProvider {
		private final AtomicInteger arrivalCalls = new AtomicInteger();
		private final AtomicInteger trainPositionCalls = new AtomicInteger();
		private final CountDownLatch arrivalEntered = new CountDownLatch(1);
		private final CountDownLatch trainPositionEntered = new CountDownLatch(1);
		private final CountDownLatch releaseArrivals = new CountDownLatch(1);
		private final CountDownLatch releaseTrainPositions = new CountDownLatch(1);

		@Override
		public List<RealtimeArrival> arrivals(RealtimeQuery query) {
			arrivalCalls.incrementAndGet();
			arrivalEntered.countDown();
			awaitRelease(releaseArrivals);
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

		@Override
		public List<RealtimeTrainPosition> trainPositions(RealtimeQuery query) {
			trainPositionCalls.incrementAndGet();
			trainPositionEntered.countDown();
			awaitRelease(releaseTrainPositions);
			return List.of(new RealtimeTrainPosition(
				"4",
				"상록수",
				"4123",
				"운행중",
				"상행",
				"당고개",
				"2026-06-26T08:00:00Z"
			));
		}

		private void awaitRelease(CountDownLatch latch) {
			try {
				if (!latch.await(1, TimeUnit.SECONDS)) {
					throw new IllegalStateException("Provider release latch timed out.");
				}
			} catch (InterruptedException exception) {
				Thread.currentThread().interrupt();
				throw new IllegalStateException("Provider wait interrupted.", exception);
			}
		}
	}

	private static final class TimeoutHttpClient extends java.net.http.HttpClient {
		@Override
		public Optional<java.net.CookieHandler> cookieHandler() {
			return Optional.empty();
		}

		@Override
		public Optional<Duration> connectTimeout() {
			return Optional.empty();
		}

		@Override
		public Redirect followRedirects() {
			return Redirect.NEVER;
		}

		@Override
		public Optional<java.net.ProxySelector> proxy() {
			return Optional.empty();
		}

		@Override
		public javax.net.ssl.SSLContext sslContext() {
			return null;
		}

		@Override
		public javax.net.ssl.SSLParameters sslParameters() {
			return null;
		}

		@Override
		public Optional<java.net.Authenticator> authenticator() {
			return Optional.empty();
		}

		@Override
		public Version version() {
			return Version.HTTP_2;
		}

		@Override
		public Optional<java.util.concurrent.Executor> executor() {
			return Optional.empty();
		}

		@Override
		public <T> java.net.http.HttpResponse<T> send(
			java.net.http.HttpRequest request,
			java.net.http.HttpResponse.BodyHandler<T> responseBodyHandler
		) throws IOException {
			throw new java.net.http.HttpTimeoutException("timeout");
		}

		@Override
		public <T> CompletableFuture<java.net.http.HttpResponse<T>> sendAsync(
			java.net.http.HttpRequest request,
			java.net.http.HttpResponse.BodyHandler<T> responseBodyHandler
		) {
			return CompletableFuture.failedFuture(new java.net.http.HttpTimeoutException("timeout"));
		}

		@Override
		public <T> CompletableFuture<java.net.http.HttpResponse<T>> sendAsync(
			java.net.http.HttpRequest request,
			java.net.http.HttpResponse.BodyHandler<T> responseBodyHandler,
			java.net.http.HttpResponse.PushPromiseHandler<T> pushPromiseHandler
		) {
			return CompletableFuture.failedFuture(new java.net.http.HttpTimeoutException("timeout"));
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
