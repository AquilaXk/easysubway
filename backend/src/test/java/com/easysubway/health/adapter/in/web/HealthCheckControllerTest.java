package com.easysubway.health.adapter.in.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import java.util.List;
import java.util.Set;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.actuate.health.Status;
import org.springframework.boot.actuate.health.StatusAggregator;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.actuate.endpoint.web.WebEndpointsSupplier;
import org.springframework.boot.test.autoconfigure.actuate.observability.AutoConfigureObservability;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(
	webEnvironment = WebEnvironment.RANDOM_PORT,
	properties = "management.endpoint.health.show-details=always"
)
@AutoConfigureObservability
@AutoConfigureMockMvc
@DisplayName("헬스체크 API")
class HealthCheckControllerTest {

	@Autowired
	private MockMvc mockMvc;

	@Autowired
	private WebEndpointsSupplier webEndpointsSupplier;

	@Autowired
	private StatusAggregator statusAggregator;

	@Test
	@DisplayName("공통 응답 형식으로 API 헬스체크를 반환한다")
	void apiHealthReturnsCommonResponse() throws Exception {
		mockMvc.perform(get("/api/health"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.success").value(true))
			.andExpect(jsonPath("$.data.status").value("UP"))
			.andExpect(jsonPath("$.data.service").value("easysubway-backend"))
			.andExpect(jsonPath("$.data.components").doesNotExist());
	}

	@Test
	@DisplayName("액추에이터 헬스체크 엔드포인트가 UP 상태를 반환한다")
	void actuatorHealthIsAvailable() throws Exception {
		mockMvc.perform(get("/actuator/health"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.status").value("UP"));
	}

	@Test
	@DisplayName("액추에이터 readiness 엔드포인트가 트래픽 수신 가능 상태를 반환한다")
	void actuatorReadinessIsAvailable() throws Exception {
		mockMvc.perform(get("/actuator/health/readiness"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.status").value("UP"));
	}

	@Test
	@DisplayName("액추에이터는 backend component health detail을 노출한다")
	void actuatorBackendComponentHealthIsAvailable() throws Exception {
		mockMvc.perform(get("/actuator/health"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.status").value("UP"))
			.andExpect(jsonPath("$.components.backendComponent.status").value("UP"))
			.andExpect(jsonPath("$.components.backendComponent.details.summaryStatus").value("UP"))
			.andExpect(jsonPath("$.components.backendComponent.details.components[0].name").value("application"));
	}

	@Test
	@DisplayName("액추에이터 status aggregator는 degraded와 stale을 UP보다 우선한다")
	void actuatorStatusAggregatorPrioritizesCustomSummaryStates() {
		assertThat(statusAggregator.getAggregateStatus(Set.of(Status.UP, new Status("DEGRADED"))).getCode())
			.isEqualTo("DEGRADED");
		assertThat(statusAggregator.getAggregateStatus(Set.of(Status.UP, new Status("STALE"))).getCode())
			.isEqualTo("STALE");
	}

	@Test
	@DisplayName("Prometheus 액추에이터 지표는 등록하되 공개 접근은 차단한다")
	void actuatorPrometheusIsNotPublic() throws Exception {
		assertThat(webEndpointsSupplier.getEndpoints())
			.extracting(endpoint -> endpoint.getEndpointId().toString())
			.contains("prometheus");

		mockMvc.perform(get("/actuator/prometheus"))
			.andExpect(status().isForbidden());
	}

	@Test
	@DisplayName("개인정보처리방침 공개 페이지를 인증 없이 노출한다")
	void privacyPolicyPageIsPublic() throws Exception {
		for (String path : List.of("/privacy", "/easysubway/privacy")) {
			mockMvc.perform(get(path))
				.andExpect(status().isOk())
				.andExpect(result -> assertThat(result.getResponse().getContentType())
					.contains("text/html", "UTF-8"))
				.andExpect(result -> assertThat(result.getResponse().getContentAsString())
					.contains(
						"쉬운 지하철 개인정보처리방침",
						"처리하는 개인정보 항목과 목적",
							"제3자 제공, 처리 위탁 및 추적",
						"외부 지도 도보 길안내",
						"카카오맵 앱",
						"카카오맵 웹",
							"이용자 및 법정대리인의 권리",
						"개인정보 보호책임자",
						"privacy@aquilaxk.site"
					));
		}
	}

	@Test
	@DisplayName("서비스 이용약관 공개 페이지를 두 경로에서 인증 없이 노출한다")
	void termsPageIsPublic() throws Exception {
		for (String path : List.of("/terms", "/easysubway/terms")) {
			mockMvc.perform(get(path))
				.andExpect(status().isOk())
				.andExpect(result -> assertThat(result.getResponse().getContentType())
					.contains("text/html", "UTF-8"))
				.andExpect(result -> assertThat(result.getResponse().getContentAsString())
					.contains("쉬운 지하철 서비스 이용약관", "서비스의 내용", "현장 안내를 우선"));
		}
	}

	@Test
	@DisplayName("위치정보 이용약관 공개 페이지를 두 경로에서 인증 없이 노출한다")
	void locationTermsPageIsPublic() throws Exception {
		for (String path : List.of("/location-terms", "/easysubway/location-terms")) {
			mockMvc.perform(get(path))
				.andExpect(status().isOk())
				.andExpect(result -> assertThat(result.getResponse().getContentType())
					.contains("text/html", "UTF-8"))
				.andExpect(result -> assertThat(result.getResponse().getContentAsString())
					.contains("쉬운 지하철 위치정보 이용약관", "제 4 조 (위치기반서비스의 내용)", "카카오맵 앱", "카카오맵 웹"));
		}
	}

	@Test
	@DisplayName("명시적으로 허용되지 않은 백엔드 경로는 기본 차단된다")
	void unknownBackendPathIsDeniedByDefault() throws Exception {
		mockMvc.perform(get("/api/v1/internal-unlisted-resource"))
			.andExpect(status().isForbidden());
	}

	@Test
	@DisplayName("파비콘 자산이 없어도 /favicon.ico는 금지(403)가 아니라 정상 404로 응답한다(#2349)")
	void faviconRequestIsNotForbiddenWhenAssetIsAbsent() throws Exception {
		// 파비콘 정적 자산이 없어 404가 나면 컨테이너가 /error로 ERROR dispatch를 forward하는데,
		// 공개 체인의 anyRequest().denyAll()이 이 dispatch까지 잡아 원래 404가 403으로 뒤바뀌던
		// 회귀를 고정한다. permitAll 파비콘 경로는 403이 아니어야 한다.
		mockMvc.perform(get("/favicon.ico"))
			.andExpect(status().isNotFound())
			.andExpect(result -> assertThat(result.getResponse().getStatus()).isNotEqualTo(403));
	}

	@Test
	@DisplayName("ERROR dispatch 경로(/error)는 공개 체인 기본 차단에서 제외된다(#2349)")
	void errorDispatchPathIsNotBlockedByPublicChain() throws Exception {
		// #2349 회귀의 실제 원인: 공개 체인 denyAll이 /error까지 차단해 404 error 렌더가 403으로 바뀌었다.
		// /error 직접 요청이 금지(403)가 아니어야 한다(허용 후 컨테이너가 원래 상태코드로 렌더).
		mockMvc.perform(get("/error"))
			.andExpect(result -> assertThat(result.getResponse().getStatus()).isNotEqualTo(403));
	}
}
