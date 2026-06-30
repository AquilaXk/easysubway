package com.easysubway.route.adapter.in.web;

import com.easysubway.common.web.ApiResponse;
import com.easysubway.profile.domain.MobilityType;
import com.easysubway.route.application.port.in.RouteSearchUseCase;
import com.easysubway.route.application.port.in.SearchRouteCommand;
import com.easysubway.route.domain.RouteSearchResult;
import com.easysubway.route.domain.RouteSearchStatus;
import com.easysubway.route.domain.RouteStep;
import com.easysubway.route.domain.RouteWarning;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import java.time.LocalDateTime;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
class RouteSearchController {

	private final RouteSearchUseCase routeSearchUseCase;

	RouteSearchController(RouteSearchUseCase routeSearchUseCase) {
		this.routeSearchUseCase = routeSearchUseCase;
	}

	@PostMapping("/api/v1/routes/search")
	ApiResponse<RouteSearchV1Response> searchRoute(@Valid @RequestBody RouteSearchRequest request) {
		return ApiResponse.ok(RouteSearchV1Response.from(routeSearchUseCase.searchRoute(request.toCommand())));
	}

	@PostMapping("/api/v2/routes/search")
	ApiResponse<RouteSearchV2Response> searchRouteV2(@Valid @RequestBody RouteSearchV2Request request) {
		return ApiResponse.ok(RouteSearchV2Response.from(routeSearchUseCase.searchRoute(request.toCommand()), request));
	}

	private record RouteSearchRequest(
		@NotBlank(message = "출발역을 선택해야 합니다.")
		String originStationId,
		@NotBlank(message = "도착역을 선택해야 합니다.")
		String destinationStationId,
		@NotNull(message = "이동 유형을 선택해야 합니다.")
		MobilityType mobilityType
	) {

		SearchRouteCommand toCommand() {
			return new SearchRouteCommand(originStationId, destinationStationId, mobilityType);
		}
	}

	private record RouteSearchV1Response(
		String routeSearchId,
		String originStationId,
		String originStationName,
		String destinationStationId,
		String destinationStationName,
		MobilityType mobilityType,
		RouteSearchStatus status,
		String lineId,
		String lineName,
		int score,
		int burdenCost,
		int estimatedDurationSeconds,
		int walkingDistanceMeters,
		int transferCount,
		List<RouteStep> steps,
		List<RouteWarning> warnings,
		List<String> blockedReasons,
		List<String> recommendationReasons,
		List<String> evidenceSummary,
		LocalDateTime createdAt,
		String etaSource,
		String routeQuality,
		boolean commercialEtaEligible
	) {

		private static RouteSearchV1Response from(RouteSearchResult result) {
			return new RouteSearchV1Response(
				result.routeSearchId(),
				result.originStationId(),
				result.originStationName(),
				result.destinationStationId(),
				result.destinationStationName(),
				result.mobilityType(),
				result.status(),
				result.lineId(),
				result.lineName(),
				result.score(),
				result.burdenCost(),
				result.estimatedDurationSeconds(),
				result.walkingDistanceMeters(),
				result.transferCount(),
				result.steps(),
				result.warnings(),
				result.blockedReasons(),
				result.recommendationReasons(),
				result.evidenceSummary(),
				result.createdAt(),
				"STATIC_BACKEND_V1",
				"LEGACY_STATIC",
				false
			);
		}
	}

	private record RouteSearchV2Request(
		@NotBlank(message = "출발역을 선택해야 합니다.")
		String originStationId,
		@NotBlank(message = "도착역을 선택해야 합니다.")
		String destinationStationId,
		@NotBlank(message = "출발 시간을 선택해야 합니다.")
		@Pattern(
			regexp = "\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(Z|[+-]\\d{2}:\\d{2})",
			message = "출발 시간은 ISO offset 형식이어야 합니다."
		)
		String departureTime,
		@NotNull(message = "이동 유형을 선택해야 합니다.")
		MobilityType mobilityType,
		@NotBlank(message = "이동 제약 조건을 선택해야 합니다.")
		String constraintMode,
		@NotNull(message = "실시간 반영 여부를 선택해야 합니다.")
		Boolean useRealtime,
		@Min(value = 0, message = "최대 환승 수는 0 이상이어야 합니다.")
		int maxTransfers,
		@Min(value = 1, message = "대안 경로 수는 1 이상이어야 합니다.")
		int alternativeCount
	) {

		SearchRouteCommand toCommand() {
			return new SearchRouteCommand(originStationId, destinationStationId, mobilityType);
		}
	}

	private record RouteSearchV2Response(
		String contractVersion,
		String originStationId,
		String destinationStationId,
		String departureTime,
		MobilityType mobilityType,
		String constraintMode,
		boolean useRealtime,
		int maxTransfers,
		int alternativeCount,
		List<String> statuses,
		List<ItineraryDto> itineraries
	) {

		private static RouteSearchV2Response from(RouteSearchResult result, RouteSearchV2Request request) {
			return new RouteSearchV2Response(
				"ROUTE_SEARCH_V2",
				request.originStationId(),
				request.destinationStationId(),
				request.departureTime(),
				request.mobilityType(),
				request.constraintMode(),
				Boolean.TRUE.equals(request.useRealtime()),
				request.maxTransfers(),
				request.alternativeCount(),
				List.of(
					"FOUND",
					"BLOCKED_ACCESSIBILITY",
					"NO_TIMETABLE_SERVICE",
					"REALTIME_UNAVAILABLE_PLANNED_USED",
					"UNSUPPORTED_REGION",
					"ROUTE_GRAPH_UNKNOWN"
				),
				List.of(ItineraryDto.from(result, OffsetDateTime.parse(request.departureTime())))
			);
		}
	}

	private record ItineraryDto(
		String itineraryId,
		String status,
		String plannedArrivalTime,
		String realtimeArrivalTime,
		String etaSource,
		String etaConfidence,
		int durationSeconds,
		int transferCount,
		int walkingDistanceMeters,
		AccessibilityRiskDto accessibilityRisk,
		List<LegDto> legs,
		boolean commercialEtaEligible
	) {

		private static ItineraryDto from(RouteSearchResult result, OffsetDateTime departureTime) {
			OffsetDateTime plannedArrivalTime = departureTime.plusSeconds(result.estimatedDurationSeconds());
			return new ItineraryDto(
				result.routeSearchId() + "-primary",
				statusOf(result),
				formatOffset(plannedArrivalTime),
				null,
				"STATIC_BACKEND_V1",
				confidenceOf(result),
				result.estimatedDurationSeconds(),
				result.transferCount(),
				result.walkingDistanceMeters(),
				AccessibilityRiskDto.from(result),
				result.steps().stream()
					.map(step -> LegDto.from(step, departureTime, plannedArrivalTime))
					.toList(),
				false
			);
		}

		private static String statusOf(RouteSearchResult result) {
			return result.status() == RouteSearchStatus.BLOCKED ? "BLOCKED_ACCESSIBILITY" : result.status().name();
		}

		private static String confidenceOf(RouteSearchResult result) {
			return result.status() == RouteSearchStatus.FOUND ? "LOW" : "UNKNOWN";
		}
	}

	private record AccessibilityRiskDto(String level, List<String> reasons) {

		private static AccessibilityRiskDto from(RouteSearchResult result) {
			List<String> reasons = result.evidenceSummary().stream()
				.filter(reason -> reason.contains("ACCESSIBILITY"))
				.toList();
			String level = reasons.isEmpty() ? "LOW" : "REVIEW_REQUIRED";
			return new AccessibilityRiskDto(level, reasons);
		}
	}

	private record LegDto(
		String legType,
		String fromStationId,
		String toStationId,
		String fromNodeId,
		String toNodeId,
		String lineId,
		String tripId,
		String trainNo,
		String plannedDepartureTime,
		String realtimeDepartureTime,
		String plannedArrivalTime,
		String realtimeArrivalTime,
		int waitTimeSeconds,
		int slackSeconds,
		int durationSeconds,
		int distanceMeters,
		String etaSource,
		String confidence,
		AccessibilityRiskDto accessibilityRisk
	) {

		private static LegDto from(RouteStep step, OffsetDateTime departureTime, OffsetDateTime plannedArrivalTime) {
			return new LegDto(
				legTypeOf(step),
				step.fromStationId(),
				step.toStationId(),
				"",
				"",
				step.lineId(),
				"",
				"",
				formatOffset(departureTime),
				null,
				formatOffset(plannedArrivalTime),
				null,
				0,
				0,
				Math.max(0, step.estimatedMinutes()) * 60,
				Math.max(0, step.distanceMeters()),
				"STATIC_BACKEND_V1",
				"LOW",
				new AccessibilityRiskDto(
					step.requiresAccessibilityCheck() ? "REVIEW_REQUIRED" : "LOW",
					step.requiresAccessibilityCheck() ? List.of("ACCESSIBILITY_CHECK_REQUIRED") : List.of()
				)
			);
		}

		private static String legTypeOf(RouteStep step) {
			return switch (step.stepType()) {
				case "exit" -> "EGRESS";
				case "ride" -> "RIDE";
				case "transfer", "internal" -> "TRANSFER";
				default -> "ACCESS";
			};
		}
	}

	private static String formatOffset(OffsetDateTime dateTime) {
		return dateTime.format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ssXXX"));
	}
}
