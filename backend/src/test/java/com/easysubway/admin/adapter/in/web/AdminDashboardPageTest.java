package com.easysubway.admin.adapter.in.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.easysubway.admin.metric.application.port.out.AdminMetricDailyRepository;
import com.easysubway.admin.metric.domain.AdminMetricDaily;
import com.easysubway.admin.metric.domain.AdminMetricKeys;
import java.time.LocalDate;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = {
	"easysubway.admin.username=admin-test",
	"easysubway.admin.password=admin-test-password"
})
@AutoConfigureMockMvc
@DisplayName("통합 대시보드 재설계")
class AdminDashboardPageTest {

	@Autowired
	private MockMvc mockMvc;

	@Autowired
	private AdminMetricDailyRepository repository;

	@Test
	@DisplayName("핵심 카드가 클릭 가능하고 스냅샷 이력이 있으면 스파크라인을 그린다")
	void rendersClickableCardsWithSparkline() throws Exception {
		repository.save(AdminMetricDaily.scalar(AdminMetricKeys.REPORTS_PENDING, LocalDate.now().minusDays(1), 3));
		repository.save(AdminMetricDaily.scalar(AdminMetricKeys.REPORTS_PENDING, LocalDate.now(), 8));

		String html = mockMvc.perform(get("/admin/dashboard/page")
				.with(httpBasic("admin-test", "admin-test-password")))
			.andExpect(status().isOk())
			.andReturn()
			.getResponse()
			.getContentAsString();

		assertThat(html)
			.contains("class=\"dashboard-card\"")
			.contains("확인할 제보")
			.contains("href=\"/admin/reports/page\"")
			.contains("dashboard-spark")
			.contains("<polyline");
	}

	@Test
	@DisplayName("지표 스냅샷 수동 재실행은 command token으로 집계 후 대시보드로 리다이렉트한다")
	void manualSnapshotRerunRedirects() throws Exception {
		MockHttpSession session = new MockHttpSession();
		String token = issueCommandToken(session);

		mockMvc.perform(post("/admin/dashboard/metrics/snapshot")
				.session(session)
				.with(httpBasic("admin-test", "admin-test-password"))
				.with(csrf())
				.param("commandToken", token))
			.andExpect(status().is3xxRedirection())
			.andExpect(header().string("Location", "/admin/dashboard/page"));
	}

	private String issueCommandToken(MockHttpSession session) throws Exception {
		String html = mockMvc.perform(get("/admin/dashboard/page")
				.session(session)
				.with(httpBasic("admin-test", "admin-test-password")))
			.andReturn()
			.getResponse()
			.getContentAsString();
		Matcher matcher = Pattern.compile("name=\"commandToken\" value=\"([^\"]+)\"").matcher(html);
		assertThat(matcher.find()).as("command token in dashboard form").isTrue();
		return matcher.group(1);
	}
}
