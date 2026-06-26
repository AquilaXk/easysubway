package com.easysubway.realtime.application;

import com.easysubway.realtime.domain.RealtimeArrival;
import com.easysubway.realtime.domain.RealtimeTrainPosition;
import java.time.Clock;
import java.time.Duration;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class RealtimeGatewayService {

	private static final Duration CACHE_TTL = Duration.ofSeconds(20);
	private static final Duration STALE_TTL = Duration.ofSeconds(120);
	private static final Duration QUOTA_CIRCUIT_OPEN = Duration.ofSeconds(60);

	private final RealtimeProvider provider;
	private final Clock clock;
	private final Map<String, CachedArrival> arrivalCache = new ConcurrentHashMap<>();
	private final Map<String, CachedTrainPosition> trainPositionCache = new ConcurrentHashMap<>();
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
		if (!supportsSangnoksu(query)) {
			return RealtimeArrivalResult.unsupported(
				"UNSUPPORTED_REGION",
				"서울 TOPIS 실시간 지원 범위 밖입니다."
			);
		}
		String cacheKey = "ARRIVALS:%s:%s:%s".formatted(query.providerLineId(), query.stationId(), query.stationQueryName());
		CachedArrival cached = arrivalCache.get(cacheKey);
		if (cached != null && isFresh(cached.cachedAt())) {
			return cached.result();
		}
		if (isQuotaCircuitOpen()) {
			return cached != null && isStaleUsable(cached.cachedAt())
				? cached.result().stale()
				: RealtimeArrivalResult.unavailable("PROVIDER_QUOTA_EXCEEDED");
		}
		try {
			RealtimeArrivalResult result = RealtimeArrivalResult.fresh(
				clock.instant().toString(),
				provider.arrivals(query)
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
		if (!supportsLine4(query)) {
			return RealtimeTrainPositionResult.unsupported(
				"UNSUPPORTED_REGION",
				"서울 TOPIS 실시간 지원 범위 밖입니다."
			);
		}
		String cacheKey = "POSITIONS:%s:%s".formatted(query.providerLineId(), query.lineName());
		CachedTrainPosition cached = trainPositionCache.get(cacheKey);
		if (cached != null && isFresh(cached.cachedAt())) {
			return cached.result();
		}
		try {
			RealtimeTrainPositionResult result = RealtimeTrainPositionResult.fresh(
				clock.instant().toString(),
				provider.trainPositions(query)
			);
			trainPositionCache.put(cacheKey, new CachedTrainPosition(result, clock.instant()));
			return result;
		} catch (RealtimeProviderException exception) {
			if (cached != null && isStaleUsable(cached.cachedAt())) {
				return cached.result().stale();
			}
			return RealtimeTrainPositionResult.unavailable(exception.fallbackCode());
		}
	}

	private boolean supportsSangnoksu(RealtimeQuery query) {
		return "station-sangnoksu".equals(query.stationId()) || "상록수".equals(query.stationQueryName());
	}

	private boolean supportsLine4(RealtimeQuery query) {
		return "4".equals(query.lineId()) || "1004".equals(query.providerLineId()) || "4호선".equals(query.lineName());
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
