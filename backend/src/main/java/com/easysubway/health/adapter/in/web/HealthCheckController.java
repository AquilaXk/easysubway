package com.easysubway.health.adapter.in.web;

import com.easysubway.common.web.ApiResponse;
import com.easysubway.health.application.port.in.CheckHealthUseCase;
import com.easysubway.health.domain.HealthComponent;
import com.easysubway.health.domain.HealthStatus;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
class HealthCheckController {

	private final CheckHealthUseCase checkHealthUseCase;

	HealthCheckController(CheckHealthUseCase checkHealthUseCase) {
		this.checkHealthUseCase = checkHealthUseCase;
	}

	@GetMapping("/api/health")
	ApiResponse<HealthCheckResponse> health() {
		return ApiResponse.ok(HealthCheckResponse.from(checkHealthUseCase.checkHealth()));
	}

	record HealthCheckResponse(String status, String service, List<HealthComponentResponse> components) {

		static HealthCheckResponse from(HealthStatus status) {
			return new HealthCheckResponse(
				status.status(),
				status.service(),
				status.components().stream().map(HealthComponentResponse::from).toList()
			);
		}
	}

	record HealthComponentResponse(String name, String status, String label, String reason) {

		static HealthComponentResponse from(HealthComponent component) {
			return new HealthComponentResponse(
				component.name(),
				component.status(),
				component.label(),
				component.reason()
			);
		}
	}
}
