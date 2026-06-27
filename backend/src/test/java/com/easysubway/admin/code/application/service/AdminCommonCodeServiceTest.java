package com.easysubway.admin.code.application.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.easysubway.admin.code.adapter.out.persistence.InMemoryAdminCommonCodeRepository;
import com.easysubway.admin.code.application.service.AdminCommonCodeService.SaveAdminCommonCodeCommand;
import com.easysubway.admin.code.domain.AdminCommonCode;
import com.easysubway.admin.code.domain.AdminCommonCodeGroups;
import com.easysubway.common.error.InvalidRequestException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("관리자 공통코드 서비스")
class AdminCommonCodeServiceTest {

	private final AdminCommonCodeService service = new AdminCommonCodeService(new InMemoryAdminCommonCodeRepository());

	@Test
	@DisplayName("공통코드는 group별로 저장하고 disabled code는 신규 선택 목록에서 제외한다")
	void saveAndDisableCommonCode() {
		AdminCommonCode saved = service.saveCode(new SaveAdminCommonCodeCommand(
			AdminCommonCodeGroups.REPORT_REJECTION_REASON,
			"OUT_OF_SCOPE",
			"처리 범위 아님",
			"앱 처리 범위 밖의 제보",
			30,
			true
		));

		assertThat(saved.enabled()).isTrue();
		assertThat(service.enabledCodes(AdminCommonCodeGroups.REPORT_REJECTION_REASON))
			.extracting(AdminCommonCode::code)
			.contains("OUT_OF_SCOPE");

		service.disableCode(AdminCommonCodeGroups.REPORT_REJECTION_REASON, "OUT_OF_SCOPE");

		assertThat(service.enabledCodes(AdminCommonCodeGroups.REPORT_REJECTION_REASON))
			.extracting(AdminCommonCode::code)
			.doesNotContain("OUT_OF_SCOPE");
		assertThat(service.listCodes(AdminCommonCodeGroups.REPORT_REJECTION_REASON, true))
			.extracting(AdminCommonCode::code)
			.contains("OUT_OF_SCOPE");
	}

	@Test
	@DisplayName("incident lifecycle 필수 코드는 비활성화할 수 없다")
	void requiredIncidentCodesCannotBeDisabled() {
		assertThatThrownBy(() -> service.disableCode(AdminCommonCodeGroups.INCIDENT_STATUS, "OPEN"))
			.isInstanceOf(InvalidRequestException.class)
			.hasMessage("필수 incident 공통코드는 비활성화할 수 없습니다.");

		assertThat(service.enabledCodes(AdminCommonCodeGroups.INCIDENT_STATUS))
			.extracting(AdminCommonCode::code)
			.contains("OPEN");
	}
}
