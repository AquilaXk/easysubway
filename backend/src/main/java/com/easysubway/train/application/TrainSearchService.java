package com.easysubway.train.application;

import com.easysubway.train.application.TrainSearchCache.CachedCatalog;
import com.easysubway.train.application.TrainSearchCache.CachedLeg;
import com.easysubway.train.application.TrainSearchProvider.Catalog;
import com.easysubway.train.application.TrainSearchProvider.ProviderFailure;
import com.easysubway.train.domain.TrainSearchModels.Journey;
import com.easysubway.train.domain.TrainSearchModels.LegQuery;
import com.easysubway.train.domain.TrainSearchModels.SearchCriteria;
import com.easysubway.train.domain.TrainSearchModels.SearchResult;
import com.easysubway.train.domain.TrainSearchModels.Station;
import com.easysubway.train.domain.TrainSearchModels.TrainType;
import com.easysubway.train.domain.TrainSearchScopePolicy;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.function.Supplier;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class TrainSearchService {

	private static final String CATALOG_KIND = "catalog";
	private static final String CATALOG_LEASE_KEY = "catalog-refresh-v1";
	private static final ZoneId PROVIDER_ZONE = ZoneId.of("Asia/Seoul");
	private static final Duration CATALOG_TTL = Duration.ofHours(24);
	private static final Duration TODAY_TTL = Duration.ofMinutes(5);
	private static final Duration FUTURE_TTL = Duration.ofHours(6);
	private static final Duration LEG_LEASE_TTL = Duration.ofSeconds(15);
	private static final Duration CATALOG_LEASE_TTL = Duration.ofMinutes(5);
	private static final List<Duration> LEASE_POLLS = List.of(
		Duration.ofMillis(100),
		Duration.ofMillis(200),
		Duration.ofMillis(400),
		Duration.ofMillis(800),
		Duration.ofSeconds(1),
		Duration.ofSeconds(1)
	);
	private static final int L1_LIMIT = 20_000;
	private static final TypeReference<List<Journey>> JOURNEYS = new TypeReference<>() {};

	private final TrainSearchProvider provider;
	private final TrainSearchCache cache;
	private final ObjectMapper objectMapper;
	private final Clock clock;
	private final Sleeper sleeper;
	private final Supplier<String> ownerSupplier;
	private final ConcurrentHashMap<String, CachedLeg> l1 = new ConcurrentHashMap<>();
	private final ConcurrentLinkedQueue<String> l1Order = new ConcurrentLinkedQueue<>();
	private final ConcurrentHashMap<String, CompletableFuture<CachedLeg>> singleFlights = new ConcurrentHashMap<>();
	private final Object catalogLock = new Object();

	@Autowired
	public TrainSearchService(TrainSearchProvider provider, TrainSearchCache cache, ObjectMapper objectMapper) {
		this(
			provider,
			cache,
			objectMapper,
			Clock.systemUTC(),
			duration -> Thread.sleep(duration.toMillis()),
			() -> UUID.randomUUID().toString()
		);
	}

	TrainSearchService(
		TrainSearchProvider provider,
		TrainSearchCache cache,
		ObjectMapper objectMapper,
		Clock clock,
		Sleeper sleeper,
		Supplier<String> ownerSupplier
	) {
		this.provider = provider;
		this.cache = cache;
		this.objectMapper = objectMapper;
		this.clock = clock;
		this.sleeper = sleeper;
		this.ownerSupplier = ownerSupplier;
	}

	public Catalog catalog() {
		try {
			Instant now = clock.instant();
			return cache.freshCatalog(CATALOG_KIND, now)
				.map(this::decodeCatalog)
				.orElseGet(() -> refreshCatalog(now));
		} catch (TrainSearchFailure failure) {
			throw failure;
		} catch (RuntimeException exception) {
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
	}

	public List<Station> stations(String query, String trainType) {
		String normalizedQuery = query == null ? "" : query.trim();
		if (normalizedQuery.codePointCount(0, normalizedQuery.length()) < 2) {
			throw failure("TRAIN_SEARCH_INVALID_ARGUMENT");
		}
		if (trainType != null) requireSupported(trainType);
		String folded = normalizedQuery.toLowerCase(Locale.ROOT);
		return catalog().stations().stream()
			.filter(station -> station.name().toLowerCase(Locale.ROOT).contains(folded))
			.sorted(Comparator.comparing(Station::name).thenComparing(Station::id))
			.toList();
	}

	public SearchResult search(SearchCriteria criteria) {
		SearchCriteria normalized = validateStructure(criteria);
		try {
			Catalog catalog = catalog();
			validateStations(normalized, catalog);
			LegResult outbound = direction(
				catalog,
				normalized.departureStationId(),
				normalized.arrivalStationId(),
				normalized.departureDate(),
				normalized.trainType()
			);
			LegResult inbound = normalized.returnDate() == null ? null : direction(
				catalog,
				normalized.arrivalStationId(),
				normalized.departureStationId(),
				normalized.returnDate(),
				normalized.trainType()
			);
			Instant observedAt = inbound == null || outbound.observedAt().isAfter(inbound.observedAt())
				? outbound.observedAt()
				: inbound.observedAt();
			return new SearchResult(
				OffsetDateTime.ofInstant(observedAt, ZoneOffset.UTC),
				outbound.journeys(),
				inbound == null ? List.of() : inbound.journeys()
			);
		} catch (TrainSearchFailure failure) {
			throw failure;
		} catch (RuntimeException exception) {
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
	}

	public Catalog refreshCatalog() {
		try {
			return refreshCatalog(clock.instant());
		} catch (TrainSearchFailure failure) {
			throw failure;
		} catch (RuntimeException exception) {
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
	}

	public int purgeExpired() {
		return cache.purgeExpiredBefore(clock.instant().minus(Duration.ofHours(48)));
	}

	private Catalog refreshCatalog(Instant now) {
		synchronized (catalogLock) {
			var existing = cache.freshCatalog(CATALOG_KIND, now);
			if (existing.isPresent()) return decodeCatalog(existing.orElseThrow());
			String owner = ownerSupplier.get();
			if (!cache.tryAcquireLease(CATALOG_LEASE_KEY, owner, now, CATALOG_LEASE_TTL)) {
				return pollForCatalog();
			}
			try {
				Catalog loaded = provider.catalog();
				Catalog filtered = new Catalog(
					loaded.observedAt(),
					loaded.stations(),
					TrainSearchScopePolicy.retainSupported(loaded.trainTypes(), TrainType::code)
				);
				String payload = write(filtered);
				cache.replaceCatalog(List.of(new CachedCatalog(
					CATALOG_KIND,
					payload,
					sha256(payload),
					filtered.observedAt(),
					now.plus(CATALOG_TTL)
				)));
				return filtered;
			} catch (ProviderFailure exception) {
				throw failure(providerFailureCode(exception));
			} finally {
				cache.releaseLease(CATALOG_LEASE_KEY, owner);
			}
		}
	}

	private Catalog pollForCatalog() {
		for (Duration delay : LEASE_POLLS) {
			sleep(delay);
			var cached = cache.freshCatalog(CATALOG_KIND, clock.instant());
			if (cached.isPresent()) return decodeCatalog(cached.orElseThrow());
		}
		throw failure("TRAIN_SEARCH_UNAVAILABLE");
	}

	private LegResult direction(
		Catalog catalog,
		String departureStationId,
		String arrivalStationId,
		LocalDate date,
		String requestedTrainType
	) {
		Station departure = station(catalog, departureStationId);
		Station arrival = station(catalog, arrivalStationId);
		List<TrainType> types = requestedTrainType == null
			? catalog.trainTypes()
			: catalog.trainTypes().stream().filter(type -> requestedTrainType.equals(type.code())).toList();
		if (types.isEmpty() || types.stream().anyMatch(type -> type.providerCodes().isEmpty())) {
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
		List<CachedLeg> legs = types.stream()
			.map(type -> leg(new LegQuery(
				departure.id(),
				arrival.id(),
				date,
				type.code(),
				type.providerCodes(),
				departure.name(),
				arrival.name()
			)))
			.toList();
		Map<String, Journey> unique = new LinkedHashMap<>();
		legs.stream()
			.flatMap(value -> decodeJourneys(value).stream())
			.sorted(Comparator.comparing(Journey::departureAt)
				.thenComparing(Journey::arrivalAt)
				.thenComparing(Journey::trainType)
				.thenComparing(Journey::trainNumber))
			.forEach(journey -> unique.putIfAbsent(journeyKey(journey), journey));
		Instant observedAt = legs.stream().map(CachedLeg::observedAt).max(Comparator.naturalOrder()).orElseThrow();
		return new LegResult(observedAt, List.copyOf(unique.values()));
	}

	private CachedLeg leg(LegQuery query) {
		String key = key(query);
		Instant now = clock.instant();
		CachedLeg local = l1.get(key);
		if (local != null && local.expiresAt().isAfter(now)) return local;
		var shared = cache.freshLeg(key, now);
		if (shared.isPresent()) {
			remember(key, shared.orElseThrow());
			return shared.orElseThrow();
		}
		var pending = new CompletableFuture<CachedLeg>();
		var existing = singleFlights.putIfAbsent(key, pending);
		if (existing != null) return await(existing);
		try {
			CachedLeg loaded = loadLeg(key, query, now);
			pending.complete(loaded);
			return loaded;
		} catch (RuntimeException exception) {
			pending.completeExceptionally(exception);
			throw exception;
		} finally {
			singleFlights.remove(key, pending);
		}
	}

	private CachedLeg loadLeg(String key, LegQuery query, Instant now) {
		String owner = ownerSupplier.get();
		if (!cache.tryAcquireLease(key, owner, now, LEG_LEASE_TTL)) return pollForShared(key);
		boolean released = false;
		try {
			List<Journey> journeys = provider.search(query);
			String normalizedQuery = write(canonical(query));
			String payload = write(journeys);
			Duration ttl = query.departureDate().equals(LocalDate.now(clock.withZone(PROVIDER_ZONE)))
				? TODAY_TTL
				: FUTURE_TTL;
			var loaded = new CachedLeg(
				key,
				normalizedQuery,
				payload,
				sha256(payload),
				now,
				now.plus(ttl)
			);
			if (!cache.storeLegAndRelease(key, owner, loaded)) throw failure("TRAIN_SEARCH_UNAVAILABLE");
			released = true;
			remember(key, loaded);
			return loaded;
		} catch (ProviderFailure exception) {
			throw failure(providerFailureCode(exception));
		} finally {
			if (!released) cache.releaseLease(key, owner);
		}
	}

	private CachedLeg pollForShared(String key) {
		for (Duration delay : LEASE_POLLS) {
			sleep(delay);
			var cached = cache.freshLeg(key, clock.instant());
			if (cached.isPresent()) {
				remember(key, cached.orElseThrow());
				return cached.orElseThrow();
			}
		}
		throw failure("TRAIN_SEARCH_UNAVAILABLE");
	}

	private SearchCriteria validateStructure(SearchCriteria criteria) {
		String departureStationId = criteria == null ? null : trimmed(criteria.departureStationId());
		String arrivalStationId = criteria == null ? null : trimmed(criteria.arrivalStationId());
		LocalDate today = LocalDate.now(clock.withZone(PROVIDER_ZONE));
		if (criteria == null
			|| blank(departureStationId)
			|| blank(arrivalStationId)
			|| Objects.equals(departureStationId, arrivalStationId)
			|| criteria.departureDate() == null
			|| criteria.departureDate().isBefore(today)
			|| (criteria.returnDate() != null && criteria.returnDate().isBefore(criteria.departureDate()))) {
			throw failure("TRAIN_SEARCH_INVALID_ARGUMENT");
		}
		String trainType = criteria.trainType() == null ? null : requireSupported(criteria.trainType());
		return new SearchCriteria(
			departureStationId,
			arrivalStationId,
			criteria.departureDate(),
			criteria.returnDate(),
			trainType
		);
	}

	private void validateStations(SearchCriteria criteria, Catalog catalog) {
		if (catalog.stations().stream().map(Station::id).noneMatch(criteria.departureStationId()::equals)
			|| catalog.stations().stream().map(Station::id).noneMatch(criteria.arrivalStationId()::equals)) {
			throw failure("TRAIN_SEARCH_INVALID_ARGUMENT");
		}
	}

	private String requireSupported(String trainType) {
		try {
			return TrainSearchScopePolicy.requireSupported(trainType);
		} catch (IllegalArgumentException exception) {
			throw failure("TRAIN_SEARCH_UNSUPPORTED_TRAIN_TYPE");
		}
	}

	private Station station(Catalog catalog, String id) {
		return catalog.stations().stream().filter(value -> id.equals(value.id())).findFirst()
			.orElseThrow(() -> failure("TRAIN_SEARCH_INVALID_ARGUMENT"));
	}

	private Map<String, Object> canonical(LegQuery query) {
		Map<String, Object> value = new LinkedHashMap<>();
		value.put("version", 1);
		value.put("departureStationId", query.departureStationId());
		value.put("arrivalStationId", query.arrivalStationId());
		value.put("departureDate", query.departureDate());
		value.put("trainType", query.trainType());
		return value;
	}

	private String key(LegQuery query) {
		return sha256(write(canonical(query)));
	}

	private String journeyKey(Journey journey) {
		return String.join(
			"|",
			journey.trainType(),
			journey.trainNumber(),
			journey.departureStationId(),
			journey.departureAt().toString(),
			journey.arrivalStationId(),
			journey.arrivalAt().toString()
		);
	}

	private Catalog decodeCatalog(CachedCatalog cached) {
		if (!Objects.equals(cached.payloadSha256(), sha256(cached.payloadJson()))) {
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
		try {
			return objectMapper.readValue(cached.payloadJson(), Catalog.class);
		} catch (JsonProcessingException exception) {
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
	}

	private List<Journey> decodeJourneys(CachedLeg cached) {
		if (!Objects.equals(cached.payloadSha256(), sha256(cached.payloadJson()))) {
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
		try {
			return objectMapper.readValue(cached.payloadJson(), JOURNEYS);
		} catch (JsonProcessingException exception) {
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
	}

	private String write(Object value) {
		try {
			return objectMapper.writeValueAsString(value);
		} catch (JsonProcessingException exception) {
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
	}

	private String sha256(String value) {
		try {
			return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
				.digest(value.getBytes(StandardCharsets.UTF_8)));
		} catch (NoSuchAlgorithmException exception) {
			throw new IllegalStateException("SHA-256 unavailable", exception);
		}
	}

	private void remember(String key, CachedLeg value) {
		CachedLeg previous = l1.put(key, value);
		if (previous == null) l1Order.add(key);
		while (l1.size() > L1_LIMIT) {
			String oldest = l1Order.poll();
			if (oldest == null) break;
			l1.remove(oldest);
		}
	}

	private CachedLeg await(CompletableFuture<CachedLeg> future) {
		try {
			return future.join();
		} catch (CompletionException exception) {
			if (exception.getCause() instanceof RuntimeException runtime) throw runtime;
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
	}

	private void sleep(Duration duration) {
		try {
			sleeper.sleep(duration);
		} catch (InterruptedException exception) {
			Thread.currentThread().interrupt();
			throw failure("TRAIN_SEARCH_UNAVAILABLE");
		}
	}

	private String providerFailureCode(ProviderFailure failure) {
		return switch (failure.getMessage()) {
			case "TRAIN_SEARCH_PROVIDER_ERROR", "TRAIN_SEARCH_NO_VALID_ROWS", "TRAIN_SEARCH_UNAVAILABLE" -> failure.getMessage();
			default -> "TRAIN_SEARCH_UNAVAILABLE";
		};
	}

	private String trimmed(String value) {
		return value == null ? null : value.trim();
	}

	private boolean blank(String value) {
		return value == null || value.isBlank();
	}

	private TrainSearchFailure failure(String code) {
		return new TrainSearchFailure(code);
	}

	private record LegResult(Instant observedAt, List<Journey> journeys) {}

	@FunctionalInterface
	interface Sleeper {
		void sleep(Duration duration) throws InterruptedException;
	}

	public static final class TrainSearchFailure extends RuntimeException {
		private final String code;

		public TrainSearchFailure(String code) {
			super(code);
			this.code = code;
		}

		public String getCode() {
			return code;
		}
	}
}
