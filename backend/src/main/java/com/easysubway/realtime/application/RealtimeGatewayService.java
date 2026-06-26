package com.easysubway.realtime.application;

import com.easysubway.realtime.domain.RealtimeArrival;
import com.easysubway.realtime.domain.RealtimeTrainPosition;
import java.time.Clock;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CompletionException;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class RealtimeGatewayService {

	private static final Duration CACHE_TTL = Duration.ofSeconds(20);
	private static final Duration STALE_TTL = Duration.ofSeconds(120);
	private static final Duration QUOTA_CIRCUIT_OPEN = Duration.ofSeconds(60);
	private static final String SANGNOKSU_STATION_ID = "station-sangnoksu";
	private static final String SANGNOKSU_STATION_NAME = "상록수";
	private static final String LINE_ID = "4";
	private static final String LINE_NAME = "4호선";
	private static final String PROVIDER_LINE_ID = "1004";

	private final RealtimeProvider provider;
	private final Clock clock;
	private final Map<String, CachedArrival> arrivalCache = new ConcurrentHashMap<>();
	private final Map<String, CachedTrainPosition> trainPositionCache = new ConcurrentHashMap<>();
	private final Map<String, CompletableFuture<RealtimeArrivalResult>> arrivalRequests = new ConcurrentHashMap<>();
	private final Map<String, CompletableFuture<RealtimeTrainPositionResult>> trainPositionRequests = new ConcurrentHashMap<>();
	private volatile java.time.Instant quotaCircuitOpenUntil;

	@Autowired
	public RealtimeGatewayService(RealtimeProvider provider) {
		this(provider, Clock.systemUTC());
	}

	RealtimeGatewayService(RealtimeProvider provider, Clock clock) {
		this.provider = provider;
		this.clock = clock;
	}

	public RealtimeArrivalResult arrivals(RealtimeQuery query) {
		RealtimeQuery normalizedQuery = normalizeArrivalQuery(query);
		if (normalizedQuery == null) {
			return RealtimeArrivalResult.unsupported(
				"UNSUPPORTED_REGION",
				"서울 TOPIS 실시간 지원 범위 밖입니다."
			);
		}
		String cacheKey = "ARRIVALS:%s:%s:%s".formatted(
			normalizedQuery.providerLineId(),
			normalizedQuery.stationId(),
			normalizedQuery.stationQueryName()
		);
		CachedArrival cached = arrivalCache.get(cacheKey);
		if (cached != null && isFresh(cached.cachedAt())) {
			return cached.result();
		}
		if (isQuotaCircuitOpen()) {
			return cached != null && isStaleUsable(cached.cachedAt())
				? cached.result().stale()
				: RealtimeArrivalResult.unavailable("PROVIDER_QUOTA_EXCEEDED");
		}
		CompletableFuture<RealtimeArrivalResult> request = new CompletableFuture<>();
		CompletableFuture<RealtimeArrivalResult> existing = arrivalRequests.putIfAbsent(cacheKey, request);
		if (existing != null) {
			return joinArrival(existing);
		}
		try {
			RealtimeArrivalResult result = fetchArrivals(normalizedQuery, cacheKey, cached);
			request.complete(result);
			return result;
		} catch (RuntimeException exception) {
			request.completeExceptionally(exception);
			throw exception;
		} finally {
			arrivalRequests.remove(cacheKey, request);
		}
	}

	private RealtimeArrivalResult fetchArrivals(RealtimeQuery normalizedQuery, String cacheKey, CachedArrival cached) {
		try {
			List<RealtimeArrival> arrivals = provider.arrivals(normalizedQuery);
			if (arrivals.isEmpty()) {
				return RealtimeArrivalResult.unavailable("EMPTY_PROVIDER_RESULT");
			}
			RealtimeArrivalResult result = RealtimeArrivalResult.fresh(
				clock.instant().toString(),
				arrivals
			);
			arrivalCache.put(cacheKey, new CachedArrival(result, clock.instant()));
			return result;
		} catch (RealtimeProviderException exception) {
			openQuotaCircuitIfNeeded(exception);
			if (cached != null && isStaleUsable(cached.cachedAt())) {
				return cached.result().stale();
			}
			return RealtimeArrivalResult.unavailable(exception.fallbackCode());
		}
	}

	public RealtimeTrainPositionResult trainPositions(RealtimeQuery query) {
		RealtimeQuery normalizedQuery = normalizeTrainPositionQuery(query);
		if (normalizedQuery == null) {
			return RealtimeTrainPositionResult.unsupported(
				"UNSUPPORTED_REGION",
				"서울 TOPIS 실시간 지원 범위 밖입니다."
			);
		}
		String cacheKey = "POSITIONS:%s:%s".formatted(normalizedQuery.providerLineId(), normalizedQuery.lineName());
		CachedTrainPosition cached = trainPositionCache.get(cacheKey);
		if (cached != null && isFresh(cached.cachedAt())) {
			return cached.result();
		}
		if (isQuotaCircuitOpen()) {
			return cached != null && isStaleUsable(cached.cachedAt())
				? cached.result().stale()
				: RealtimeTrainPositionResult.unavailable("PROVIDER_QUOTA_EXCEEDED");
		}
		CompletableFuture<RealtimeTrainPositionResult> request = new CompletableFuture<>();
		CompletableFuture<RealtimeTrainPositionResult> existing = trainPositionRequests.putIfAbsent(cacheKey, request);
		if (existing != null) {
			return joinTrainPosition(existing);
		}
		try {
			RealtimeTrainPositionResult result = fetchTrainPositions(normalizedQuery, cacheKey, cached);
			request.complete(result);
			return result;
		} catch (RuntimeException exception) {
			request.completeExceptionally(exception);
			throw exception;
		} finally {
			trainPositionRequests.remove(cacheKey, request);
		}
	}

	private RealtimeTrainPositionResult fetchTrainPositions(
		RealtimeQuery normalizedQuery,
		String cacheKey,
		CachedTrainPosition cached
	) {
		try {
			List<RealtimeTrainPosition> trainPositions = provider.trainPositions(normalizedQuery);
			if (trainPositions.isEmpty()) {
				return RealtimeTrainPositionResult.unavailable("EMPTY_PROVIDER_RESULT");
			}
			RealtimeTrainPositionResult result = RealtimeTrainPositionResult.fresh(
				clock.instant().toString(),
				trainPositions
			);
			trainPositionCache.put(cacheKey, new CachedTrainPosition(result, clock.instant()));
			return result;
		} catch (RealtimeProviderException exception) {
			openQuotaCircuitIfNeeded(exception);
			if (cached != null && isStaleUsable(cached.cachedAt())) {
				return cached.result().stale();
			}
			return RealtimeTrainPositionResult.unavailable(exception.fallbackCode());
		}
	}

	private RealtimeArrivalResult joinArrival(CompletableFuture<RealtimeArrivalResult> request) {
		try {
			return request.join();
		} catch (CompletionException exception) {
			throw unwrapCompletionException(exception);
		}
	}

	private RealtimeTrainPositionResult joinTrainPosition(CompletableFuture<RealtimeTrainPositionResult> request) {
		try {
			return request.join();
		} catch (CompletionException exception) {
			throw unwrapCompletionException(exception);
		}
	}

	private RuntimeException unwrapCompletionException(CompletionException exception) {
		Throwable cause = exception.getCause();
		if (cause instanceof RuntimeException runtimeException) {
			return runtimeException;
		}
		return exception;
	}

	private RealtimeQuery normalizeArrivalQuery(RealtimeQuery query) {
		if (!SANGNOKSU_STATION_ID.equals(query.stationId()) || !SANGNOKSU_STATION_NAME.equals(query.stationQueryName())) {
			return null;
		}
		if (!isBlankOrOneOf(query.lineId(), LINE_ID, "seoul-4")) {
			return null;
		}
		if (!isBlankOrOneOf(query.providerLineId(), PROVIDER_LINE_ID, "448")) {
			return null;
		}
		return new RealtimeQuery(
			SANGNOKSU_STATION_ID,
			LINE_ID,
			PROVIDER_LINE_ID,
			SANGNOKSU_STATION_NAME,
			LINE_NAME
		);
	}

	private RealtimeQuery normalizeTrainPositionQuery(RealtimeQuery query) {
		if (!LINE_NAME.equals(query.lineName())) {
			return null;
		}
		if (!isBlankOrOneOf(query.lineId(), LINE_ID, "seoul-4")) {
			return null;
		}
		if (!isBlankOrOneOf(query.providerLineId(), PROVIDER_LINE_ID)) {
			return null;
		}
		return new RealtimeQuery(
			SANGNOKSU_STATION_ID,
			LINE_ID,
			PROVIDER_LINE_ID,
			SANGNOKSU_STATION_NAME,
			LINE_NAME
		);
	}

	private boolean isBlankOrOneOf(String value, String... allowedValues) {
		if (value == null || value.isBlank()) {
			return true;
		}
		for (String allowedValue : allowedValues) {
			if (allowedValue.equals(value)) {
				return true;
			}
		}
		return false;
	}

	private boolean isFresh(java.time.Instant cachedAt) {
		return Duration.between(cachedAt, clock.instant()).compareTo(CACHE_TTL) <= 0;
	}

	private boolean isStaleUsable(java.time.Instant cachedAt) {
		return Duration.between(cachedAt, clock.instant()).compareTo(STALE_TTL) <= 0;
	}

	private boolean isQuotaCircuitOpen() {
		java.time.Instant openUntil = quotaCircuitOpenUntil;
		return openUntil != null && clock.instant().isBefore(openUntil);
	}

	private void openQuotaCircuitIfNeeded(RealtimeProviderException exception) {
		if ("PROVIDER_QUOTA_EXCEEDED".equals(exception.fallbackCode())) {
			quotaCircuitOpenUntil = clock.instant().plus(QUOTA_CIRCUIT_OPEN);
		}
	}

	private record CachedArrival(RealtimeArrivalResult result, java.time.Instant cachedAt) {
	}

	private record CachedTrainPosition(RealtimeTrainPositionResult result, java.time.Instant cachedAt) {
	}
}
