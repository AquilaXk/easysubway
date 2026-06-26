package com.easysubway.admin.operations.adapter.in.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.easysubway.admin.audit.adapter.out.persistence.InMemoryAdminAuditEventRepository;
import com.easysubway.admin.audit.domain.AdminAuditEventType;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest(properties = {
	"easysubway.admin.username=admin-user",
	"easysubway.admin.password=admin-test-password"
})
@AutoConfigureMockMvc
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_EACH_TEST_METHOD)
@DisplayName("관리자 공통코드와 장애관리 화면")
class AdminOperationsPageControllerTest {

	@Autowired
	private MockMvc mockMvc;

	@Autowired
	private InMemoryAdminAuditEventRepository auditEventRepository;

	@Test
	@DisplayName("공통코드 화면은 group filter와 enabled/disabled code를 표시한다")
	void codesPageShowsGroupFilterAndCodes() throws Exception {
		String html = mockMvc.perform(get("/admin/codes/page")
				.with(httpBasic("admin-user", "admin-test-password")))
			.andExpect(status().isOk())
			.andReturn()
			.getResponse()
			.getContentAsString();

		assertThat(html)
			.contains("공통코드")
			.contains("신고 반려 사유")
			.contains("DUPLICATE")
			.contains("신규 선택 가능");
	}

	@Test
	@DisplayName("공통코드 변경은 audit을 남긴다")
	void saveCodeWritesAudit() throws Exception {
		mockMvc.perform(post("/admin/codes")
				.with(httpBasic("admin-user", "admin-test-password"))
				.with(csrf())
				.contentType(MediaType.APPLICATION_FORM_URLENCODED)
				.param("groupCode", "REPORT_REJECTION_REASON")
				.param("code", "PROVIDER_SECRET_MISSING")
				.param("displayName", "처리 범위 아님")
				.param("description", "앱 처리 범위 밖의 제보")
				.param("sortOrder", "30")
				.param("enabled", "true"))
			.andExpect(status().is3xxRedirection())
			.andExpect(header().string("Location", "/admin/codes/page?groupCode=REPORT_REJECTION_REASON"));

		assertThat(auditEventRepository.findRecent(AdminAuditEventType.COMMON_CODE_CHANGE, 1))
			.singleElement()
			.satisfies(event -> {
				assertThat(event.actor()).isEqualTo("admin-user");
				assertThat(event.targetId())
					.startsWith("REPORT_REJECTION_REASON:code-")
					.doesNotContain("SECRET");
				assertThat(event.action()).isEqualTo("UPSERT_COMMON_CODE");
				assertThat(event.reason()).isEqualTo("enabled=true");
			});
	}

	@Test
	@DisplayName("장애관리 화면은 enabled code select와 incident 목록을 표시한다")
	void incidentsPageShowsSelectOptions() throws Exception {
		String html = mockMvc.perform(get("/admin/incidents/page")
				.with(httpBasic("admin-user", "admin-test-password")))
			.andExpect(status().isOk())
			.andReturn()
			.getResponse()
			.getContentAsString();

		assertThat(html)
			.contains("장애관리")
			.contains("Major")
			.contains("Open")
			.contains("Health incident 생성");
	}

	@Test
	@DisplayName("incident 생성과 해결은 audit을 남긴다")
	void incidentOpenAndResolveWritesAudit() throws Exception {
		mockMvc.perform(post("/admin/incidents")
				.with(httpBasic("admin-user", "admin-test-password"))
				.with(csrf())
				.contentType(MediaType.APPLICATION_FORM_URLENCODED)
				.param("severity", "MAJOR")
				.param("status", "OPEN")
				.param("source", "HEALTH")
				.param("summary", "database DOWN")
				.param("owner", "ops"))
			.andExpect(status().is3xxRedirection())
			.andExpect(header().string("Location", "/admin/incidents/page"));

		String incidentId = auditEventRepository.findRecent(AdminAuditEventType.INCIDENT_CHANGE, 1)
			.get(0)
			.targetId();

		assertThat(incidentId).startsWith("INC-");

		mockMvc.perform(post("/admin/incidents/{incidentId}/resolve", incidentId)
				.with(httpBasic("admin-user", "admin-test-password"))
				.with(csrf())
				.contentType(MediaType.APPLICATION_FORM_URLENCODED)
				.param("resolution", "provider secret upload url rotated"))
			.andExpect(status().is3xxRedirection())
			.andExpect(header().string("Location", "/admin/incidents/page"));

		assertThat(auditEventRepository.findRecent(AdminAuditEventType.INCIDENT_CHANGE, 2))
			.extracting(event -> event.action())
			.containsExactly("RESOLVE_INCIDENT", "OPEN_INCIDENT");

		assertThat(auditEventRepository.findRecent(AdminAuditEventType.INCIDENT_CHANGE, 1))
			.singleElement()
			.satisfies(event -> {
				assertThat(event.actor()).isEqualTo("admin-user");
				assertThat(event.targetId()).isEqualTo(incidentId);
				assertThat(event.action()).isEqualTo("RESOLVE_INCIDENT");
				assertThat(event.reason()).startsWith("resolutionLength=");
				assertThat(event.reason()).doesNotContain("secret");
			});
	}
}
