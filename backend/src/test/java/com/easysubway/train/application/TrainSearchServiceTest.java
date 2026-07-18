package com.easysubway.train.application;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.groups.Tuple.tuple;

import com.easysubway.train.application.TrainSearchCache.CachedCatalog;
import com.easysubway.train.application.TrainSearchCache.CachedLeg;
import com.easysubway.train.application.TrainSearchProvider.Catalog;
import com.easysubway.train.domain.TrainSearchModels.Journey;
import com.easysubway.train.domain.TrainSearchModels.LegQuery;
import com.easysubway.train.domain.TrainSearchModels.SearchCriteria;
import com.easysubway.train.domain.TrainSearchModels.Station;
import com.easysubway.train.domain.TrainSearchModels.TrainType;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class TrainSearchServiceTest {

	private static final Instant NOW = Instant.parse("2026-07-19T00:00:00Z");
	private FakeProvider provider;
	private FakeCache cache;
	private TrainSearchService service;

	@BeforeEach
	void setUp() {
		provider = new FakeProvider();
		cache = new FakeCache();
		service = new TrainSearchService(
			provider,
			cache,
			new ObjectMapper().registerModule(new JavaTimeModule()),
			Clock.fixed(NOW, ZoneOffset.UTC),
			duration -> {},
			() -> "owner"
		);
	}

	@Test
	void joinsConcurrentMissesIntoOneProviderSearch() throws Exception {
		provider.blockSearch = true;
		var first = CompletableFuture.supplyAsync(() -> service.search(criteria(null)));
		assertThat(provider.searchStarted.await(5, TimeUnit.SECONDS)).isTrue();
		var second = CompletableFuture.supplyAsync(() -> service.search(criteria(null)));
		provider.continueSearch.countDown();

		assertThat(first.get(5, TimeUnit.SECONDS)).isEqualTo(second.get(5, TimeUnit.SECONDS));
		assertThat(provider.searchCalls).hasValue(1);
	}

	@Test
	void passesEveryProviderCodeAndStationNameInOneCanonicalLegQuery() {
		service.search(criteria(null));

		assertThat(provider.queries).singleElement().satisfies(query -> {
			assertThat(query.trainType()).isEqualTo("KTX");
			assertThat(query.providerTrainGradeCodes()).containsExactly("00", "10");
			assertThat(query.departureStationName()).isEqualTo("서울");
			assertThat(query.arrivalStationName()).isEqualTo("대전");
		});
	}

	@Test
	void usesFiveMinutesForTodayAndSixHoursForFutureRoundTrip() {
		var snapshot = service.searchWithMetadata(criteria(LocalDate.parse("2026-07-21")));
		var result = snapshot.result();

		assertThat(result.outbound()).hasSize(1);
		assertThat(result.inbound()).hasSize(1);
		assertThat(provider.queries).extracting(LegQuery::departureStationId, LegQuery::arrivalStationId)
			.containsExactly(
				tuple("NAT010000", "NAT011668"),
				tuple("NAT011668", "NAT010000")
			);
		assertThat(cache.legs.values()).extracting(CachedLeg::expiresAt)
			.containsExactlyInAnyOrder(NOW.plus(Duration.ofMinutes(5)), NOW.plus(Duration.ofHours(6)));
		assertThat(snapshot.expiresAt()).isEqualTo(NOW.plus(Duration.ofMinutes(5)));
	}

	@Test
	void refreshesAFutureEntryWhenItsDepartureDateBecomesTodayInKorea() {
		service = serviceAt(Instant.parse("2026-07-19T14:59:00Z"));
		service.search(criteriaFor(LocalDate.parse("2026-07-20"), null));

		service = serviceAt(Instant.parse("2026-07-19T15:00:00Z"));
		service.search(criteriaFor(LocalDate.parse("2026-07-20"), null));

		assertThat(provider.searchCalls).hasValue(2);
	}

	@Test
	void keepsTheLegLeaseBeyondTheBoundedProviderSearchWindow() {
		service.search(criteria(null));

		assertThat(cache.leaseTtls.values())
			.anySatisfy(ttl -> assertThat(ttl).isGreaterThanOrEqualTo(Duration.ofMinutes(15)));
	}

	@Test
	void scheduledCatalogRefreshReplacesAStillFreshCatalog() {
		service.catalog();

		service.refreshCatalog();

		assertThat(provider.catalogCalls).hasValue(2);
	}

	@Test
	void rejectsInvalidInputsBeforeSearchingAndKeepsItxOutOfTheCatalog() {
		assertThatThrownBy(() -> service.stations("서", null))
			.isInstanceOf(TrainSearchService.TrainSearchFailure.class)
			.extracting("code")
			.isEqualTo("TRAIN_SEARCH_INVALID_ARGUMENT");
		assertThatThrownBy(() -> service.search(new SearchCriteria(
			"UNKNOWN", "NAT011668", LocalDate.parse("2026-07-19"), null, "KTX"
		)))
			.isInstanceOf(TrainSearchService.TrainSearchFailure.class)
			.extracting("code")
			.isEqualTo("TRAIN_SEARCH_INVALID_ARGUMENT");

		assertThat(service.stations("서울", "KTX")).extracting(Station::name).containsExactly("서울");
		assertThat(service.catalog().trainTypes()).extracting(TrainType::code)
			.containsExactly("KTX")
			.doesNotContain("ITX_CHEONGCHUN");
		assertThat(provider.searchCalls).hasValue(0);
	}

	@Test
	void rejectsStructurallyInvalidSearchBeforeCatalogLookup() {
		assertThatThrownBy(() -> service.search(null))
			.isInstanceOf(TrainSearchService.TrainSearchFailure.class)
			.extracting("code")
			.isEqualTo("TRAIN_SEARCH_INVALID_ARGUMENT");

		assertThat(provider.catalogCalls).hasValue(0);
	}

	@Test
	void rejectsCatalogAndLegPayloadsWhoseSha256DoesNotMatch() {
		service.catalog();
		CachedCatalog catalog = cache.catalogs.get("catalog");
		cache.catalogs.put("catalog", new CachedCatalog(
			catalog.kind(), catalog.payloadJson(), "0".repeat(64), catalog.observedAt(), catalog.expiresAt()
		));

		assertThatThrownBy(() -> newService().catalog())
			.isInstanceOf(TrainSearchService.TrainSearchFailure.class)
			.extracting("code")
			.isEqualTo("TRAIN_SEARCH_UNAVAILABLE");

		cache.catalogs.clear();
		service.search(criteria(null));
		CachedLeg leg = cache.legs.values().iterator().next();
		cache.legs.put(leg.key(), new CachedLeg(
			leg.key(), leg.normalizedQueryJson(), leg.payloadJson(), "0".repeat(64), leg.observedAt(), leg.expiresAt()
		));

		assertThatThrownBy(() -> newService().search(criteria(null)))
			.isInstanceOf(TrainSearchService.TrainSearchFailure.class)
			.extracting("code")
			.isEqualTo("TRAIN_SEARCH_UNAVAILABLE");
	}

	@Test
	void mapsCacheReadFailureToUnavailable() {
		cache.failCatalogRead = true;

		assertThatThrownBy(service::catalog)
			.isInstanceOf(TrainSearchService.TrainSearchFailure.class)
			.extracting("code")
			.isEqualTo("TRAIN_SEARCH_UNAVAILABLE");
	}

	@Test
	void mapsProviderQuotaFailureToUnavailableWithoutServingAnExpiredRow() {
		service.search(criteria(null));
		CachedLeg fresh = cache.legs.values().iterator().next();
		cache.legs.put(fresh.key(), new CachedLeg(
			fresh.key(),
			fresh.normalizedQueryJson(),
			fresh.payloadJson(),
			fresh.payloadSha256(),
			fresh.observedAt(),
			NOW.minusSeconds(1)
		));
		provider.failureCode = "TRAIN_SEARCH_UNAVAILABLE";

		assertThatThrownBy(() -> newService().search(criteria(null)))
			.isInstanceOf(TrainSearchService.TrainSearchFailure.class)
			.extracting("code")
			.isEqualTo("TRAIN_SEARCH_UNAVAILABLE");
	}

	@Test
	void hashesTheCanonicalLegKeyWithoutProviderCodesOrCredentials() {
		service.search(criteria(null));

		assertThat(cache.legs.keySet()).singleElement().satisfies(key -> assertThat(key).matches("^[0-9a-f]{64}$"));
		assertThat(cache.legs.values()).singleElement().satisfies(leg -> {
			assertThat(leg.normalizedQueryJson()).doesNotContain(
				"providerTrainGradeCodes", "departureStationName", "arrivalStationName", "serviceKey"
			);
			assertThat(leg.normalizedQueryJson()).contains("NAT010000", "NAT011668", "KTX");
		});
	}

	private SearchCriteria criteria(LocalDate returnDate) {
		return criteriaFor(LocalDate.parse("2026-07-19"), returnDate);
	}

	private SearchCriteria criteriaFor(LocalDate departureDate, LocalDate returnDate) {
		return new SearchCriteria(
			"NAT010000", "NAT011668", departureDate, returnDate, "KTX"
		);
	}

	private TrainSearchService serviceAt(Instant instant) {
		return new TrainSearchService(
			provider,
			cache,
			new ObjectMapper().registerModule(new JavaTimeModule()),
			Clock.fixed(instant, ZoneOffset.UTC),
			duration -> {},
			() -> "owner"
		);
	}

	private TrainSearchService newService() {
		return new TrainSearchService(
			provider,
			cache,
			new ObjectMapper().registerModule(new JavaTimeModule()),
			Clock.fixed(NOW, ZoneOffset.UTC),
			duration -> {},
			() -> "owner"
		);
	}

	private static final class FakeProvider implements TrainSearchProvider {
		private final AtomicInteger catalogCalls = new AtomicInteger();
		private final AtomicInteger searchCalls = new AtomicInteger();
		private final List<LegQuery> queries = new java.util.concurrent.CopyOnWriteArrayList<>();
		private final CountDownLatch searchStarted = new CountDownLatch(1);
		private final CountDownLatch continueSearch = new CountDownLatch(1);
		private volatile boolean blockSearch;
		private volatile String failureCode;

		@Override
		public Catalog catalog() {
			catalogCalls.incrementAndGet();
			return new Catalog(
				NOW,
				List.of(new Station("NAT010000", "서울"), new Station("NAT011668", "대전")),
				List.of(
					new TrainType("KTX", "KTX", List.of("00", "10")),
					new TrainType("ITX_CHEONGCHUN", "ITX-청춘", List.of("09"))
				)
			);
		}

		@Override
		public List<Journey> search(LegQuery query) {
			if (failureCode != null) throw new ProviderFailure(failureCode);
			searchCalls.incrementAndGet();
			queries.add(query);
			searchStarted.countDown();
			if (blockSearch) {
				try {
					continueSearch.await(5, TimeUnit.SECONDS);
				} catch (InterruptedException exception) {
					Thread.currentThread().interrupt();
				}
			}
			return List.of(new Journey(
				"101", "KTX",
				query.departureStationId(), query.departureStationName(),
				OffsetDateTime.parse(query.departureDate() + "T09:00:00+09:00"),
				query.arrivalStationId(), query.arrivalStationName(),
				OffsetDateTime.parse(query.departureDate() + "T10:00:00+09:00"),
				60, 10_000
			));
		}
	}

	private static final class FakeCache implements TrainSearchCache {
		private final Map<String, CachedCatalog> catalogs = new ConcurrentHashMap<>();
		private final Map<String, CachedLeg> legs = new ConcurrentHashMap<>();
		private final Map<String, String> leases = new ConcurrentHashMap<>();
		private final Map<String, Duration> leaseTtls = new ConcurrentHashMap<>();
		private volatile boolean failCatalogRead;

		@Override
		public Optional<CachedCatalog> freshCatalog(String kind, Instant now) {
			if (failCatalogRead) throw new IllegalStateException("database unavailable");
			return Optional.ofNullable(catalogs.get(kind)).filter(value -> value.expiresAt().isAfter(now));
		}

		@Override
		public void replaceCatalog(List<CachedCatalog> values) {
			catalogs.clear();
			values.forEach(value -> catalogs.put(value.kind(), value));
		}

		@Override
		public Optional<CachedLeg> freshLeg(String key, Instant now) {
			return Optional.ofNullable(legs.get(key)).filter(value -> value.expiresAt().isAfter(now));
		}

		@Override
		public boolean tryAcquireLease(String key, String owner, Instant now, Duration ttl) {
			leaseTtls.put(key, ttl);
			return leases.putIfAbsent(key, owner) == null;
		}

		@Override
		public void releaseLease(String key, String owner) {
			leases.remove(key, owner);
		}

		@Override
		public boolean storeLegAndRelease(String key, String owner, CachedLeg leg) {
			if (!leases.remove(key, owner)) return false;
			legs.put(key, leg);
			return true;
		}

		@Override
		public boolean tryAcquireProviderCall(String providerId, ZoneId providerZone, int minuteLimit, int dayLimit) {
			return true;
		}

		@Override
		public int purgeExpiredBefore(Instant cutoff) {
			int before = legs.size();
			legs.values().removeIf(value -> value.expiresAt().isBefore(cutoff));
			return before - legs.size();
		}
	}
}
