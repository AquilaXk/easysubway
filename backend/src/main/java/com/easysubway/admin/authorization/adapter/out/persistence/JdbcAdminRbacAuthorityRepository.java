package com.easysubway.admin.authorization.adapter.out.persistence;

import com.easysubway.admin.authorization.AdminRbacRole;
import com.easysubway.admin.authorization.application.port.out.AdminRbacAuthorityRepository;
import java.time.Clock;
import java.time.LocalDateTime;
import java.util.Locale;
import java.util.Set;
import java.util.stream.Collectors;
import javax.sql.DataSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Profile;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
@Profile("prod | staging | release | prod-like")
public class JdbcAdminRbacAuthorityRepository implements AdminRbacAuthorityRepository {

	private final JdbcTemplate jdbcTemplate;

	@Autowired
	public JdbcAdminRbacAuthorityRepository(DataSource dataSource) {
		this.jdbcTemplate = new JdbcTemplate(dataSource);
	}

	@Override
	public Set<String> findPermissionAuthorities(String loginId) {
		return jdbcTemplate.queryForList("""
			SELECT DISTINCT rp.permission_code
			FROM admin_user_roles ur
			JOIN admin_role_permissions rp ON rp.role_code = ur.role_code
			WHERE ur.login_id = ?
			""", String.class, normalize(loginId))
			.stream()
			.collect(Collectors.toUnmodifiableSet());
	}

	@Override
	public void seedRole(String loginId, AdminRbacRole role) {
		if (role == null) {
			return;
		}
		String canonicalLoginId = normalize(loginId);
		Integer existing = jdbcTemplate.queryForObject("""
			SELECT COUNT(*)
			FROM admin_user_roles
			WHERE login_id = ? AND role_code = ?
			""", Integer.class, canonicalLoginId, role.name());
		if (existing != null && existing > 0) {
			return;
		}
		try {
			jdbcTemplate.update("""
				INSERT INTO admin_user_roles (created_at, role_code, login_id)
				VALUES (?, ?, ?)
				""", LocalDateTime.now(Clock.systemUTC()), role.name(), canonicalLoginId);
		} catch (DuplicateKeyException exception) {
			// 동시 부팅이 이미 동일 role 할당을 seed한 경우이므로 멱등하게 무시한다.
		}
	}

	private static String normalize(String loginId) {
		return loginId == null ? "" : loginId.trim().toLowerCase(Locale.ROOT);
	}
}
