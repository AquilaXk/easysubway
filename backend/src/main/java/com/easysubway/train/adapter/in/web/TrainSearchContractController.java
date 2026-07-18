package com.easysubway.train.adapter.in.web;

import com.easysubway.common.web.ApiResponse;
import com.easysubway.train.application.TrainSearchService;
import com.easysubway.train.application.TrainSearchService.TrainSearchFailure;
import com.easysubway.train.domain.TrainSearchModels.SearchCriteria;
import com.easysubway.train.domain.TrainSearchScopePolicy;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.util.HexFormat;
import java.util.concurrent.TimeUnit;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.context.request.WebRequest;

@RestController
class TrainSearchContractController {

	private static final ZoneId KOREA = ZoneId.of("Asia/Seoul");
	private static final CachePolicy STATION_CACHE = new CachePolicy(300, 86_400);
	private static final CachePolicy TODAY_CACHE = new CachePolicy(60, 300);
	private static final CachePolicy FUTURE_CACHE = new CachePolicy(300, 21_600);
	private static final CacheControl NO_STORE = CacheControl.noStore();

	private final TrainSearchService service;
	private final ObjectMapper objectMapper;
	private final Clock clock;

	TrainSearchContractController(
		TrainSearchService service,
		ObjectMapper objectMapper,
		ObjectProvider<Clock> clockProvider
	) {
		this.service = service;
		this.objectMapper = objectMapper;
		this.clock = clockProvider.getIfAvailable(Clock::systemUTC);
	}

	@GetMapping("/api/v1/trains/stations")
	ResponseEntity<ApiResponse<?>> stations(
		@RequestParam(required = false) String query,
		@RequestParam(required = false) String trainType,
		WebRequest webRequest
	) {
		try {
			validateTrainType(trainType);
			var snapshot = service.stationsWithMetadata(query, trainType);
			return success(snapshot.stations(), snapshot.expiresAt(), STATION_CACHE, webRequest);
		} catch (IllegalArgumentException exception) {
			return error(HttpStatus.BAD_REQUEST, "TRAIN_SEARCH_UNSUPPORTED_TRAIN_TYPE", "지원하지 않는 열차종입니다.");
		} catch (TrainSearchFailure failure) {
			return error(failureStatus(failure), failure.getCode(), failureMessage(failure));
		}
	}

	@GetMapping("/api/v1/trains/search")
	ResponseEntity<ApiResponse<?>> search(
		@RequestParam(required = false) String departureStationId,
		@RequestParam(required = false) String arrivalStationId,
		@RequestParam(required = false) String departureDate,
		@RequestParam(required = false) String returnDate,
		@RequestParam(required = false) String trainType,
		WebRequest webRequest
	) {
		try {
			validateTrainType(trainType);
			LocalDate outboundDate = parseRequiredDate(departureDate);
			LocalDate inboundDate = returnDate == null || returnDate.isBlank() ? null : LocalDate.parse(returnDate);
			var criteria = new SearchCriteria(
				departureStationId,
				arrivalStationId,
				outboundDate,
				inboundDate,
				trainType
			);
			CachePolicy cachePolicy = outboundDate.equals(clock.instant().atZone(KOREA).toLocalDate())
				? TODAY_CACHE
				: FUTURE_CACHE;
			var snapshot = service.searchWithMetadata(criteria);
			return success(snapshot.result(), snapshot.expiresAt(), cachePolicy, webRequest);
		} catch (DateTimeParseException | NullPointerException exception) {
			return error(HttpStatus.BAD_REQUEST, "TRAIN_SEARCH_INVALID_ARGUMENT", "검색 조건을 확인해 주세요.");
		} catch (IllegalArgumentException exception) {
			return error(HttpStatus.BAD_REQUEST, "TRAIN_SEARCH_UNSUPPORTED_TRAIN_TYPE", "지원하지 않는 열차종입니다.");
		} catch (TrainSearchFailure failure) {
			return error(failureStatus(failure), failure.getCode(), failureMessage(failure));
		}
	}

	private ResponseEntity<ApiResponse<?>> success(
		Object data,
		java.time.Instant expiresAt,
		CachePolicy cachePolicy,
		WebRequest webRequest
	) {
		ApiResponse<Object> envelope = ApiResponse.ok(data);
		String etag = etag(envelope);
		CacheControl cacheControl = cacheControl(expiresAt, cachePolicy);
		if (matchesIfNoneMatch(webRequest.getHeaderValues("If-None-Match"), etag)) {
			return ResponseEntity.status(HttpStatus.NOT_MODIFIED)
				.eTag(etag)
				.cacheControl(cacheControl)
				.build();
		}
		return ResponseEntity.ok()
			.eTag(etag)
			.cacheControl(cacheControl)
			.body(envelope);
	}

	private boolean matchesIfNoneMatch(String[] headerValues, String etag) {
		if (headerValues == null) return false;
		String current = withoutWeakPrefix(etag);
		for (String headerValue : headerValues) {
			for (String validator : headerValue.split(",")) {
				String candidate = validator.trim();
				if ("*".equals(candidate) || current.equals(withoutWeakPrefix(candidate))) return true;
			}
		}
		return false;
	}

	private String withoutWeakPrefix(String etag) {
		return etag.startsWith("W/") ? etag.substring(2).trim() : etag;
	}

	private CacheControl cacheControl(java.time.Instant expiresAt, CachePolicy policy) {
		long remaining = Math.max(0, Duration.between(clock.instant(), expiresAt).getSeconds());
		CacheControl result = CacheControl.maxAge(Math.min(policy.clientSeconds(), remaining), TimeUnit.SECONDS)
			.cachePublic()
			.sMaxAge(Math.min(policy.sharedSeconds(), remaining), TimeUnit.SECONDS);
		return remaining == 0 ? result.mustRevalidate() : result;
	}

	private ResponseEntity<ApiResponse<?>> error(HttpStatus status, String code, String message) {
		return ResponseEntity.status(status)
			.cacheControl(NO_STORE)
			.body(new ApiResponse<>(false, new TrainSearchError(code), message));
	}

	private HttpStatus failureStatus(TrainSearchFailure failure) {
		return switch (failure.getCode()) {
			case "TRAIN_SEARCH_INVALID_ARGUMENT" -> HttpStatus.UNPROCESSABLE_ENTITY;
			case "TRAIN_SEARCH_PROVIDER_ERROR", "TRAIN_SEARCH_NO_VALID_ROWS" -> HttpStatus.BAD_GATEWAY;
			default -> HttpStatus.SERVICE_UNAVAILABLE;
		};
	}

	private String failureMessage(TrainSearchFailure failure) {
		return switch (failure.getCode()) {
			case "TRAIN_SEARCH_INVALID_ARGUMENT" -> "검색 조건을 확인해 주세요.";
			case "TRAIN_SEARCH_PROVIDER_ERROR" -> "기차 정보 제공기관 응답을 처리하지 못했습니다.";
			case "TRAIN_SEARCH_NO_VALID_ROWS" -> "유효한 열차 시간표를 확인하지 못했습니다.";
			default -> "기차검색을 일시적으로 사용할 수 없습니다.";
		};
	}

	private LocalDate parseRequiredDate(String value) {
		if (value == null || value.isBlank()) throw new NullPointerException("departureDate is required");
		return LocalDate.parse(value);
	}

	private void validateTrainType(String trainType) {
		if (trainType != null) TrainSearchScopePolicy.requireSupported(trainType);
	}

	private String etag(ApiResponse<?> envelope) {
		try {
			byte[] bytes = objectMapper.writeValueAsString(envelope).getBytes(StandardCharsets.UTF_8);
			return "\"" + HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)) + "\"";
		} catch (JsonProcessingException | NoSuchAlgorithmException exception) {
			throw new IllegalStateException("train-search response fingerprint failed", exception);
		}
	}

	record TrainSearchError(String code) {}

	private record CachePolicy(long clientSeconds, long sharedSeconds) {}
}
