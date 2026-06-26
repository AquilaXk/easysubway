package com.easysubway.admin.identity.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.admin.identity.domain.AdminIdentity;
import com.easysubway.admin.identity.domain.AdminIdentityAuthMethod;
import com.easysubway.admin.identity.domain.AdminIdentityRole;
import com.easysubway.admin.identity.domain.AdminIdentityStatus;
import com.easysubway.admin.identity.domain.AdminLoginAudit;
import java.time.Duration;
import java.time.LocalDateTime;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseBuilder;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

@DisplayName("JDBC 관리자 identity 저장소")
class JdbcAdminIdentityRepositoryTest {

	@Test
	@DisplayName("관리자 계정 상태와 로그인 감사 기록을 DB에 저장한다")
	void saveIdentityAndLoginAudit() {
		var dataSource = new EmbeddedDatabaseBuilder()
			.setType(EmbeddedDatabaseType.H2)
			.generateUniqueName(true)
			.build();
		new ResourceDatabasePopulator(new ClassPathResource("db/migration/h2/V9__admin_identity.sql"))
			.execute(dataSource);
		var repository = new JdbcAdminIdentityRepository(dataSource);
		var jdbcTemplate = new JdbcTemplate(dataSource);
		LocalDateTime now = LocalDateTime.of(2026, 6, 27, 0, 0);

		repository.save(localIdentity("admin-user", now));
		repository.save(repository.findByLoginId("admin-user").orElseThrow()
			.recordFailure(now.plusMinutes(1), 1, Duration.ofMinutes(15)));
		repository.recordLoginAudit(new AdminLoginAudit(
			"admin-user",
			AdminIdentityAuthMethod.LOCAL,
			"LOCKED",
			null,
			now.plusMinutes(1)
		));

		var loaded = repository.findByLoginId("ADMIN-USER").orElseThrow();
		assertThat(loaded.failedLoginCount()).isEqualTo(1);
		assertThat(loaded.lockedUntil()).isEqualTo(now.plusMinutes(16));
		assertThat(loaded.role()).isEqualTo(AdminIdentityRole.ADMIN);
		assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM admin_login_audits", Integer.class))
			.isEqualTo(1);
	}

	private AdminIdentity localIdentity(String loginId, LocalDateTime now) {
		return new AdminIdentity(
			loginId,
			"관리자",
			"admin@example.com",
			"{noop}admin-password",
			AdminIdentityAuthMethod.LOCAL,
			AdminIdentityRole.ADMIN,
			AdminIdentityStatus.ACTIVE,
			0,
			null,
			now,
			null,
			false,
			null,
			now,
			now
		);
	}
}
