package com.easysubway.admin.identity.adapter.out.persistence;

import com.easysubway.admin.identity.application.port.out.AdminIdentityRepository;
import com.easysubway.admin.identity.domain.AdminIdentity;
import com.easysubway.admin.identity.domain.AdminIdentityAuthMethod;
import com.easysubway.admin.identity.domain.AdminIdentityRole;
import com.easysubway.admin.identity.domain.AdminIdentityStatus;
import com.easysubway.admin.identity.domain.AdminLoginAudit;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.util.Locale;
import java.util.Optional;
import javax.sql.DataSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Profile;
import org.springframework.dao.EmptyResultDataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
@Profile("prod")
public class JdbcAdminIdentityRepository implements AdminIdentityRepository {

	private final JdbcTemplate jdbcTemplate;

	@Autowired
	public JdbcAdminIdentityRepository(DataSource dataSource) {
		this(new JdbcTemplate(dataSource));
	}

	JdbcAdminIdentityRepository(JdbcTemplate jdbcTemplate) {
		this.jdbcTemplate = jdbcTemplate;
	}

	@Override
	public Optional<AdminIdentity> findByLoginId(String loginId) {
		try {
			return Optional.ofNullable(jdbcTemplate.queryForObject(
				"""
					SELECT login_id, display_name, email, password_hash, auth_method, role, status,
						failed_login_count, locked_until, password_changed_at, password_expires_at,
						credential_rotation_required, break_glass_reason, created_at, updated_at
					FROM admin_users
					WHERE login_id = ?
					""",
				this::mapIdentity,
				normalize(loginId)
			));
		} catch (EmptyResultDataAccessException exception) {
			return Optional.empty();
		}
	}

	@Override
	public AdminIdentity save(AdminIdentity identity) {
		int updated = jdbcTemplate.update("""
			UPDATE admin_users
			SET display_name = ?,
				email = ?,
				password_hash = ?,
				auth_method = ?,
				role = ?,
				status = ?,
				failed_login_count = ?,
				locked_until = ?,
				password_changed_at = ?,
				password_expires_at = ?,
				credential_rotation_required = ?,
				break_glass_reason = ?,
				updated_at = ?
			WHERE login_id = ?
			""",
			identity.displayName(),
			identity.email(),
			identity.passwordHash(),
			identity.authMethod().name(),
			identity.role().name(),
			identity.status().name(),
			identity.failedLoginCount(),
			identity.lockedUntil(),
			identity.passwordChangedAt(),
			identity.passwordExpiresAt(),
			identity.credentialRotationRequired(),
			identity.breakGlassReason(),
			identity.updatedAt(),
			normalize(identity.loginId())
		);
		if (updated == 0) {
			insert(identity);
		}
		return identity;
	}

	@Override
	public AdminIdentity upsertBootstrap(AdminIdentity identity) {
		if (findByLoginId(identity.loginId()).isPresent()) {
			return findByLoginId(identity.loginId()).orElseThrow();
		}
		insert(identity);
		return identity;
	}

	@Override
	public void recordLoginAudit(AdminLoginAudit audit) {
		jdbcTemplate.update("""
			INSERT INTO admin_login_audits (login_id, auth_method, outcome, reason, occurred_at)
			VALUES (?, ?, ?, ?, ?)
			""",
			normalize(audit.loginId()),
			audit.authMethod().name(),
			audit.outcome(),
			audit.reason(),
			audit.occurredAt()
		);
	}

	private void insert(AdminIdentity identity) {
		jdbcTemplate.update("""
			INSERT INTO admin_users (
				login_id, display_name, email, password_hash, auth_method, role, status,
				failed_login_count, locked_until, password_changed_at, password_expires_at,
				credential_rotation_required, break_glass_reason, created_at, updated_at
			)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
			""",
			normalize(identity.loginId()),
			identity.displayName(),
			identity.email(),
			identity.passwordHash(),
			identity.authMethod().name(),
			identity.role().name(),
			identity.status().name(),
			identity.failedLoginCount(),
			identity.lockedUntil(),
			identity.passwordChangedAt(),
			identity.passwordExpiresAt(),
			identity.credentialRotationRequired(),
			identity.breakGlassReason(),
			identity.createdAt(),
			identity.updatedAt()
		);
	}

	private AdminIdentity mapIdentity(ResultSet resultSet, int rowNumber) throws SQLException {
		return new AdminIdentity(
			resultSet.getString("login_id"),
			resultSet.getString("display_name"),
			resultSet.getString("email"),
			resultSet.getString("password_hash"),
			AdminIdentityAuthMethod.valueOf(resultSet.getString("auth_method")),
			AdminIdentityRole.valueOf(resultSet.getString("role")),
			AdminIdentityStatus.valueOf(resultSet.getString("status")),
			resultSet.getInt("failed_login_count"),
			toLocalDateTime(resultSet.getTimestamp("locked_until")),
			resultSet.getTimestamp("password_changed_at").toLocalDateTime(),
			toLocalDateTime(resultSet.getTimestamp("password_expires_at")),
			resultSet.getBoolean("credential_rotation_required"),
			resultSet.getString("break_glass_reason"),
			resultSet.getTimestamp("created_at").toLocalDateTime(),
			resultSet.getTimestamp("updated_at").toLocalDateTime()
		);
	}

	private static java.time.LocalDateTime toLocalDateTime(Timestamp timestamp) {
		return timestamp == null ? null : timestamp.toLocalDateTime();
	}

	private static String normalize(String loginId) {
		return loginId == null ? "" : loginId.trim().toLowerCase(Locale.ROOT);
	}
}
