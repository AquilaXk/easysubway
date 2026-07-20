package com.easysubway.admin.authorization.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.admin.authorization.AdminRbacRole;
import javax.sql.DataSource;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseBuilder;
import org.springframework.jdbc.datasource.embedded.EmbeddedDatabaseType;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

@DisplayName("JDBC 관리자 RBAC authority 저장소")
class JdbcAdminRbacAuthorityRepositoryTest {

	@Test
	@DisplayName("SUPER_ADMIN role seed는 canonical 로그인 ID로 전체 permission authority를 부여한다")
	void seedSuperAdminRoleGrantsAllPermissionAuthorities() {
		var dataSource = rbacDataSource();
		var repository = new JdbcAdminRbacAuthorityRepository(dataSource);

		repository.seedRole("Env-Admin", AdminRbacRole.SUPER_ADMIN);

		assertThat(repository.findPermissionAuthorities("env-admin"))
			.contains(
				"admin.view",
				"admin.report.review",
				"admin.master.edit",
				"admin.field.operate",
				"admin.data.operate",
				"admin.security.audit",
				"admin.security.admin"
			);
	}

	@Test
	@DisplayName("동일 role seed를 반복해도 admin_user_roles 행은 하나만 유지한다")
	void seedRoleIsIdempotent() {
		var dataSource = rbacDataSource();
		var repository = new JdbcAdminRbacAuthorityRepository(dataSource);
		var jdbcTemplate = new JdbcTemplate(dataSource);

		repository.seedRole("env-admin", AdminRbacRole.SUPER_ADMIN);
		repository.seedRole("env-admin", AdminRbacRole.SUPER_ADMIN);

		assertThat(jdbcTemplate.queryForObject(
			"SELECT COUNT(*) FROM admin_user_roles WHERE login_id = ? AND role_code = ?",
			Integer.class,
			"env-admin",
			"SUPER_ADMIN"
		)).isEqualTo(1);
	}

	private DataSource rbacDataSource() {
		var dataSource = new EmbeddedDatabaseBuilder()
			.setType(EmbeddedDatabaseType.H2)
			.generateUniqueName(true)
			.build();
		new ResourceDatabasePopulator(new ClassPathResource("db/migration/h2/V10__admin_rbac_menu.sql"))
			.execute(dataSource);
		return dataSource;
	}
}
