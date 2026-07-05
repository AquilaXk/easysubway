package com.easysubway.admin.metric.adapter.in.web;

import static org.hamcrest.Matchers.nullValue;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.user;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.easysubway.admin.authorization.AdminPermission;
import com.easysubway.admin.metric.application.port.out.AdminMetricDailyRepository;
import com.easysubway.admin.metric.domain.AdminMetricDaily;
import com.easysubway.admin.metric.domain.AdminMetricKeys;
import java.time.LocalDate;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

@SpringBootTest(properties = {
	"easysubway.admin.username=admin-test",
	"easysubway.admin.password=admin-test-password"
})
@AutoConfigureMockMvc
@DisplayName("분석 데이터 API")
class AdminAnalyticsMetricControllerTest {

	@Autowired
	private MockMvc mockMvc;

	@Autowired
	private AdminMetricDailyRepository repository;

	@BeforeEach
	void seed() {
		repository.save(AdminMetricDaily.scalar(AdminMetricKeys.ROUTE_SEARCHES, LocalDate.now(), 40));
		repository.save(AdminMetricDaily.scalar(AdminMetricKeys.ROUTE_SEARCHES, LocalDate.now().minusDays(7), 10));
	}

	@Test
	@DisplayName("분석 시계열을 키·기간으로 돌려주고 결측일은 null로 채운다")
	void returnsTimeSeries() throws Exception {
		mockMvc.perform(get("/admin/analytics/metrics")
				.param("keys", AdminMetricKeys.ROUTE_SEARCHES)
				.param("days", "7")
				.with(httpBasic("admin-test", "admin-test-password")))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.days").value(7))
			.andExpect(jsonPath("$.labels.length()").value(7))
			.andExpect(jsonPath("$.series[0].key").value(AdminMetricKeys.ROUTE_SEARCHES))
			.andExpect(jsonPath("$.series[0].values[6]").value(40.0))
			.andExpect(jsonPath("$.series[0].values[0]").value(nullValue()));
	}

	@Test
	@DisplayName("기간 비교는 최근·직전 합계와 증감을 돌려준다")
	void returnsComparison() throws Exception {
		mockMvc.perform(get("/admin/analytics/comparison")
				.param("keys", AdminMetricKeys.ROUTE_SEARCHES)
				.param("days", "7")
				.with(httpBasic("admin-test", "admin-test-password")))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$[0].key").value(AdminMetricKeys.ROUTE_SEARCHES))
			.andExpect(jsonPath("$[0].current").value(40.0))
			.andExpect(jsonPath("$[0].previous").value(10.0))
			.andExpect(jsonPath("$[0].delta").value(30.0))
			.andExpect(jsonPath("$[0].deltaPercent").value(300.0));
	}

	@Test
	@DisplayName("ADMIN_VIEW 권한이면 분석 데이터를 볼 수 있다")
	void adminViewCanReadAnalytics() throws Exception {
		RequestPostProcessor viewer = user("viewer")
			.authorities(new SimpleGrantedAuthority(AdminPermission.ADMIN_VIEW.authority()));

		mockMvc.perform(get("/admin/analytics/metrics").param("days", "30").with(viewer))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.labels.length()").value(30));
	}
}
