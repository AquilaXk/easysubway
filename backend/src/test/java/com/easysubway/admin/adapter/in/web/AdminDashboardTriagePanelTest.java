package com.easysubway.admin.adapter.in.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.easysubway.datapack.application.port.in.DatapackReleaseBlockerSummaryUseCase;
import com.easysubway.datapack.application.port.in.DatapackReleaseBlockerSummaryUseCase.DatapackReleaseBlockerSummary;
import com.easysubway.quality.application.port.in.DataQualityUseCase;
import com.easysubway.quality.domain.DataQualitySummary;
import com.easysubway.report.application.port.in.FacilityReportUseCase;
import com.easysubway.report.domain.FacilityReportStatus;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

/**
 * "확인 필요" 통합 트리아지 카드(#2349 PR⑦) 렌더링 검증. 실제 DB 상태로는 제보·시설·데이터팩
 * 차단 요인 건수를 결정적으로 만들기 어려워, {@link AdminAlertRenderingTest}와 같은 패턴으로
 * 값을 주입하는 use case를 대체(MockBean)해 0건 생략·전부 0 폴백·데이터팩 상세 표의 0건 행 숨김을 고정한다.
 */
@SpringBootTest(properties = {
	"easysubway.admin.username=admin-test",
	"easysubway.admin.password=admin-test-password"
})
@AutoConfigureMockMvc
@DisplayName("통합 대시보드 확인 필요 카드")
class AdminDashboardTriagePanelTest {

	@Autowired
	private MockMvc mockMvc;

	@MockBean
	private FacilityReportUseCase facilityReportUseCase;

	@MockBean
	private DataQualityUseCase dataQualityUseCase;

	@MockBean
	private DatapackReleaseBlockerSummaryUseCase datapackReleaseBlockerSummaryUseCase;

	@Test
	@DisplayName("0건이 아닌 항목만 라벨·건수·딥링크로 보여준다")
	void showsOnlyNonZeroItemsWithDeepLinks() throws Exception {
		when(facilityReportUseCase.countReportsByStatus())
			.thenReturn(Map.of(FacilityReportStatus.SUBMITTED, 5L));
		when(facilityReportUseCase.countReportsCreatedSince(any())).thenReturn(0L);
		when(dataQualityUseCase.summarizeDataQuality()).thenReturn(dataQualitySummary(0));
		when(datapackReleaseBlockerSummaryUseCase.summarize()).thenReturn(blockerSummary(0, 0, 0, 0, 0, 0, 0));

		String triage = triageSection(fetchDashboard());

		assertThat(triage)
			.contains("확인할 제보")
			.contains(">5건<")
			.contains("href=\"/admin/reports/page\"")
			// 확인 필요 시설·데이터팩 차단 요인은 0건이라 딥링크 자체가 빠진다(라벨 텍스트는 섹션
			// 안내 주석에도 나오므로 href로 스코핑한다).
			.doesNotContain("href=\"/admin/facilities/page\"")
			.doesNotContain("href=\"#dashboard-datapack-readiness\"");
	}

	@Test
	@DisplayName("전부 0건이면 카드 대신 한 줄 상태 텍스트만 보여준다")
	void fallsBackToOneLineStatusWhenAllZero() throws Exception {
		when(facilityReportUseCase.countReportsByStatus()).thenReturn(Map.of());
		when(facilityReportUseCase.countReportsCreatedSince(any())).thenReturn(0L);
		when(dataQualityUseCase.summarizeDataQuality()).thenReturn(dataQualitySummary(0));
		when(datapackReleaseBlockerSummaryUseCase.summarize()).thenReturn(blockerSummary(0, 0, 0, 0, 0, 0, 0));

		String html = fetchDashboard();

		assertThat(html)
			.contains("class=\"admin-status good dashboard-triage-empty\"")
			.contains("지금 확인할 항목이 없습니다")
			.doesNotContain("id=\"dashboard-triage-title\"");
	}

	@Test
	@DisplayName("데이터팩 차단 요인 상세 표는 0건 카테고리를 숨기고 비-0만 노출한 뒤 숨긴 건수를 요약한다")
	void datapackBlockerDetailHidesZeroRowsAndSummarizesHidden() throws Exception {
		when(facilityReportUseCase.countReportsByStatus()).thenReturn(Map.of());
		when(facilityReportUseCase.countReportsCreatedSince(any())).thenReturn(0L);
		when(dataQualityUseCase.summarizeDataQuality()).thenReturn(dataQualitySummary(0));
		// 별칭 2건·매니페스트 서명 1건만 non-zero, 나머지 5개 카테고리(후보 게이트·격리·수동 오버라이드·
		// 시설 근거·경로 게이트)는 0건.
		when(datapackReleaseBlockerSummaryUseCase.summarize()).thenReturn(blockerSummary(2, 0, 0, 0, 0, 0, 1));

		String details = blockerDetailsSection(fetchDashboard());

		assertThat(details)
			.contains("<th scope=\"row\">별칭</th>")
			.contains("<th scope=\"row\">매니페스트 서명</th>")
			.contains("그 외 항목 5건은 0건입니다")
			.doesNotContain("<th scope=\"row\">후보 게이트</th>")
			.doesNotContain("<th scope=\"row\">격리</th>")
			.doesNotContain("<th scope=\"row\">수동 오버라이드</th>")
			.doesNotContain("<th scope=\"row\">시설 근거</th>")
			.doesNotContain("<th scope=\"row\">경로 게이트</th>")
			.doesNotContain("차단 요인이 없습니다.");
	}

	@Test
	@DisplayName("데이터팩 차단 요인이 전부 0건이면 상세 표 대신 빈 상태 문법을 적용한다")
	void datapackBlockerDetailShowsEmptyStateWhenAllZero() throws Exception {
		when(facilityReportUseCase.countReportsByStatus()).thenReturn(Map.of());
		when(facilityReportUseCase.countReportsCreatedSince(any())).thenReturn(0L);
		when(dataQualityUseCase.summarizeDataQuality()).thenReturn(dataQualitySummary(0));
		when(datapackReleaseBlockerSummaryUseCase.summarize()).thenReturn(blockerSummary(0, 0, 0, 0, 0, 0, 0));

		String details = blockerDetailsSection(fetchDashboard());

		assertThat(details)
			.contains("차단 요인이 없습니다.")
			.doesNotContain("그 외 항목")
			.doesNotContain("<th scope=\"row\">별칭</th>");
	}

	@Test
	@DisplayName("후보가 없어 candidateId가 결측이면 - 원문 대신 — 로 표기한다")
	void showsEmDashInsteadOfRawDashForMissingCandidateId() throws Exception {
		when(facilityReportUseCase.countReportsByStatus()).thenReturn(Map.of());
		when(facilityReportUseCase.countReportsCreatedSince(any())).thenReturn(0L);
		when(dataQualityUseCase.summarizeDataQuality()).thenReturn(dataQualitySummary(0));
		when(datapackReleaseBlockerSummaryUseCase.summarize()).thenReturn(DatapackReleaseBlockerSummary.empty());

		String html = fetchDashboard();

		assertThat(html)
			.contains("<strong>—</strong>")
			.doesNotContain("<strong>-</strong>");
	}

	private String fetchDashboard() throws Exception {
		return mockMvc.perform(get("/admin/dashboard/page")
				.with(httpBasic("admin-test", "admin-test-password")))
			.andExpect(status().isOk())
			.andReturn()
			.getResponse()
			.getContentAsString();
	}

	private String triageSection(String html) {
		int start = html.indexOf("<!-- 확인 필요");
		int end = html.indexOf("<!-- 긴급 줄", start);
		assertThat(start).as("확인 필요 영역 시작 마커").isGreaterThan(-1);
		assertThat(end).as("긴급 줄 영역 시작 마커").isGreaterThan(start);
		return html.substring(start, end);
	}

	private String blockerDetailsSection(String html) {
		int start = html.indexOf("상세 해시·워크플로 보기");
		int end = html.indexOf("</details>", start);
		assertThat(start).as("데이터팩 상세 표 시작 지점").isGreaterThan(-1);
		assertThat(end).as("데이터팩 상세 표 종료 지점").isGreaterThan(start);
		return html.substring(start, end);
	}

	private static DataQualitySummary dataQualitySummary(long needsVerificationFacilityCount) {
		return new DataQualitySummary(
			0, 0, 0,
			Map.of(),
			List.of(),
			Map.of(),
			Map.of(),
			needsVerificationFacilityCount,
			0,
			Map.of(),
			0,
			List.of(),
			List.of()
		);
	}

	private static DatapackReleaseBlockerSummary blockerSummary(
		long alias,
		long quarantine,
		long manualOverride,
		long routeGate,
		long candidateGate,
		long facility,
		long manifest
	) {
		long total = alias + quarantine + manualOverride + routeGate + candidateGate + facility + manifest;
		return new DatapackReleaseBlockerSummary(
			"candidate-triage-test",
			"scope-triage-test",
			"a".repeat(64),
			"b".repeat(64),
			"c".repeat(64),
			"https://github.com/AquilaXk/easysubway/actions/runs/1",
			"candidate-prod-triage-test",
			"candidate-rollback-triage-test",
			total > 0 ? "FAIL" : "READY",
			total,
			candidateGate,
			alias,
			quarantine,
			0,
			manualOverride,
			facility,
			routeGate,
			manifest,
			List.of(),
			null
		);
	}
}
