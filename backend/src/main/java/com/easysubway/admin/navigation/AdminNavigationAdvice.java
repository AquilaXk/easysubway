package com.easysubway.admin.navigation;

import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.core.env.Environment;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ModelAttribute;

@ControllerAdvice
class AdminNavigationAdvice {

	private final Environment environment;

	AdminNavigationAdvice(Environment environment) {
		this.environment = environment;
	}

	@ModelAttribute("adminProgramIds")
	Set<String> adminProgramIds(Authentication authentication) {
		return AdminProgram.visibleTo(authentication).stream()
			.map(AdminProgram::id)
			.collect(Collectors.toUnmodifiableSet());
	}

	@ModelAttribute("adminProgramGroups")
	List<AdminProgramGroup> adminProgramGroups(Authentication authentication) {
		return AdminProgram.visibleTo(authentication).stream()
			.collect(Collectors.groupingBy(
				AdminProgram::groupLabel,
				java.util.LinkedHashMap::new,
				Collectors.toList()
			))
			.entrySet()
			.stream()
			.map(entry -> new AdminProgramGroup(entry.getKey(), entry.getValue()))
			.toList();
	}

	@ModelAttribute("adminShell")
	AdminShell adminShell(Authentication authentication) {
		String username = isAuthenticated(authentication) ? authentication.getName() : "anonymous";
		List<String> roles = roleNames(authentication);
		return new AdminShell(
			environmentLabel(),
			environmentTone(),
			username,
			rolesLabel(authentication),
			roles.size(),
			rolesTitle(roles),
			environment.getProperty("easysubway.admin.revision", "local"),
			environment.getProperty("easysubway.admin.master-data-version", "unknown")
		);
	}

	private String environmentLabel() {
		List<String> profiles = activeProfiles();
		if (profiles.contains("staging")) {
			return "STAGING";
		}
		if (profiles.contains("prod")) {
			return "PRODUCTION";
		}
		return profiles.isEmpty() ? "DEV" : profiles.get(0).toUpperCase(java.util.Locale.ROOT);
	}

	private String environmentTone() {
		List<String> profiles = activeProfiles();
		if (profiles.contains("staging")) {
			return "staging";
		}
		if (profiles.contains("prod")) {
			return "production";
		}
		return "development";
	}

	private List<String> activeProfiles() {
		return Arrays.stream(environment.getActiveProfiles()).toList();
	}

	private static List<String> roleNames(Authentication authentication) {
		if (!isAuthenticated(authentication)) {
			return List.of();
		}
		return authentication.getAuthorities().stream()
			.map(authority -> authority.getAuthority().replaceFirst("^ROLE_", ""))
			.sorted(Comparator.naturalOrder())
			.toList();
	}

	private static String rolesLabel(Authentication authentication) {
		List<String> authorities = roleNames(authentication);
		if (authorities.isEmpty()) {
			return "권한 없음";
		}
		if (authorities.size() == 1) {
			return authorities.get(0);
		}
		return authorities.get(0) + " 외 " + (authorities.size() - 1) + "개";
	}

	// 상태 스트립 툴팁용 전체 역할 목록. 상단바는 "권한 N개"만 보이고 의미는 이 title로 설명한다.
	private static String rolesTitle(List<String> roles) {
		if (roles.isEmpty()) {
			return "부여된 권한이 없습니다";
		}
		return "부여된 권한: " + String.join(", ", roles);
	}

	private static boolean isAuthenticated(Authentication authentication) {
		return authentication != null
			&& authentication.isAuthenticated()
			&& !(authentication instanceof AnonymousAuthenticationToken);
	}

	record AdminProgramGroup(String label, List<AdminProgram> programs) {
	}

	record AdminShell(
		String environmentLabel,
		String environmentTone,
		String username,
		String rolesLabel,
		int rolesCount,
		String rolesTitle,
		String revision,
		String masterDataVersion
	) {
	}
}
