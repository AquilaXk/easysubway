package com.easysubway.admin.code.application.service;

import com.easysubway.admin.code.application.port.out.AdminCommonCodeRepository;
import com.easysubway.admin.code.domain.AdminCommonCode;
import com.easysubway.admin.code.domain.AdminCommonCodeGroup;
import com.easysubway.admin.code.domain.AdminCommonCodeGroups;
import com.easysubway.common.error.InvalidRequestException;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class AdminCommonCodeService {

	private final AdminCommonCodeRepository repository;
	private final Clock clock;

	@Autowired
	public AdminCommonCodeService(AdminCommonCodeRepository repository) {
		this(repository, Clock.systemUTC());
	}

	AdminCommonCodeService(AdminCommonCodeRepository repository, Clock clock) {
		this.repository = repository;
		this.clock = clock;
	}

	public List<AdminCommonCodeGroup> listGroups() {
		return repository.findGroups();
	}

	public List<AdminCommonCode> listCodes(String groupCode, boolean includeDisabled) {
		return repository.findCodes(groupCode)
			.stream()
			.filter(code -> includeDisabled || code.enabled())
			.toList();
	}

	public List<AdminCommonCode> enabledCodes(String groupCode) {
		return listCodes(groupCode, false);
	}

	public AdminCommonCode saveCode(SaveAdminCommonCodeCommand command) {
		AdminCommonCodeGroup group = repository.findGroup(command.groupCode())
			.orElseThrow(() -> new InvalidRequestException("허용되지 않은 공통코드 group입니다."));
		if (!group.enabled()) {
			throw new InvalidRequestException("비활성 공통코드 group에는 code를 추가할 수 없습니다.");
		}
		LocalDateTime now = LocalDateTime.now(clock);
		AdminCommonCode existing = repository.findCode(command.groupCode(), command.code()).orElse(null);
		LocalDateTime createdAt = existing == null ? now : existing.createdAt();
		boolean enabled = AdminCommonCodeGroups.isRequiredIncidentCode(command.groupCode(), command.code())
			|| command.enabled();
		return repository.saveCode(new AdminCommonCode(
			command.groupCode(),
			command.code(),
			command.displayName(),
			command.description(),
			command.sortOrder(),
			enabled,
			createdAt,
			now
		));
	}

	public AdminCommonCode disableCode(String groupCode, String code) {
		if (AdminCommonCodeGroups.isRequiredIncidentCode(groupCode, code)) {
			throw new InvalidRequestException("필수 incident 공통코드는 비활성화할 수 없습니다.");
		}
		AdminCommonCode existing = repository.findCode(groupCode, code)
			.orElseThrow(() -> new InvalidRequestException("비활성화할 공통코드를 찾을 수 없습니다."));
		return repository.saveCode(existing.withEnabled(false, LocalDateTime.now(clock)));
	}

	public record SaveAdminCommonCodeCommand(
		String groupCode,
		String code,
		String displayName,
		String description,
		int sortOrder,
		boolean enabled
	) {
	}
}
