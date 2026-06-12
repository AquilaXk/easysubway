package com.easysubway.route.adapter.in.web;

import com.easysubway.common.web.ApiResponse;
import com.easysubway.profile.domain.MobilityType;
import com.easysubway.route.application.port.in.RouteSearchUseCase;
import com.easysubway.route.application.port.in.SearchRouteCommand;
import com.easysubway.route.domain.RouteSearchResult;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
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
	ApiResponse<RouteSearchResult> searchRoute(@RequestBody SearchRouteRequest request) {
		return ApiResponse.ok(routeSearchUseCase.searchRoute(request.toCommand()));
	}

	@GetMapping("/api/v1/routes/{routeSearchId}")
	ApiResponse<RouteSearchResult> getRouteSearch(@PathVariable String routeSearchId) {
		return ApiResponse.ok(routeSearchUseCase.getRouteSearch(routeSearchId));
	}

	record SearchRouteRequest(
		String originStationId,
		String destinationStationId,
		MobilityType mobilityType
	) {

		SearchRouteCommand toCommand() {
			return new SearchRouteCommand(originStationId, destinationStationId, mobilityType);
		}
	}
}
