package com.easysubway.admin.transition;

import java.util.List;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "easysubway.admin.platform-transition")
public record AdminPlatformTransitionProperties(
	Stage stage,
	Flags flags,
	ShadowMode rbacShadow,
	ShadowMode auditShadow,
	LegacyEnvAdminFallback legacyEnvAdminFallback,
	BreakGlass breakGlass,
	Seed seed,
	Rollback rollback,
	ReleaseGate releaseGate
) {

	public AdminPlatformTransitionProperties {
		stage = stage == null ? Stage.SHADOW : stage;
		flags = flags == null ? Flags.defaults() : flags;
		rbacShadow = rbacShadow == null ? ShadowMode.rbacDefaults() : rbacShadow;
		auditShadow = auditShadow == null ? ShadowMode.auditDefaults() : auditShadow;
		legacyEnvAdminFallback = legacyEnvAdminFallback == null
			? LegacyEnvAdminFallback.defaults()
			: legacyEnvAdminFallback;
		breakGlass = breakGlass == null ? BreakGlass.defaults() : breakGlass;
		seed = seed == null ? Seed.defaults() : seed;
		rollback = rollback == null ? Rollback.defaults() : rollback;
		releaseGate = releaseGate == null ? ReleaseGate.defaults() : releaseGate;
	}

	public enum Stage {
		SHADOW,
		ENFORCE,
		LEGACY_DISABLED
	}

	public enum BlockerMode {
		WARN,
		FAIL
	}

	public record Flags(
		boolean identityStore,
		boolean rbacShadow,
		boolean rbacEnforcement,
		boolean auditShadow,
		boolean auditEnforcement,
		boolean legacyEnvAdminFallback,
		boolean breakGlassBootstrap,
		boolean roleSeedRequired
	) {

		static Flags defaults() {
			return new Flags(true, true, false, true, false, true, true, true);
		}
	}

	public record ShadowMode(
		String mode,
		String metric,
		List<String> promotionCriteria
	) {

		static ShadowMode rbacDefaults() {
			return new ShadowMode(
				"compare-and-log",
				"admin_rbac_shadow_denial_total",
				List.of(
					"admin_role_permissions seed includes every AdminPermission",
					"admin_user_roles seed covers each production administrator",
					"shadow denial metric is zero for one release cycle"
				)
			);
		}

		static ShadowMode auditDefaults() {
			return new ShadowMode(
				"write-and-compare",
				"admin_audit_shadow_missing_total",
				List.of(
					"admin_audit_events records login and privileged admin actions",
					"privacy reads and break-glass use include actor, permission, request id",
					"missing audit metric is zero for one release cycle"
				)
			);
		}
	}

	public record LegacyEnvAdminFallback(
		List<String> removalCriteria,
		String rollbackAction
	) {

		static LegacyEnvAdminFallback defaults() {
			return new LegacyEnvAdminFallback(
				List.of(
					"all production admins have admin_users rows with role seed",
					"break-glass bootstrap account was rotated after first use",
					"rollback has been tested with the previous env admin secret"
				),
				"restore EASYSUBWAY_ADMIN_USERNAME and EASYSUBWAY_ADMIN_PASSWORD, keep RBAC enforcement disabled, and redeploy previous release"
			);
		}
	}

	public record BreakGlass(
		String issueProcedure,
		String rotationProcedure
	) {

		static BreakGlass defaults() {
			return new BreakGlass(
				"create short-lived EASYSUBWAY_ADMIN_BREAK_GLASS_USERNAME, PASSWORD, and REASON secrets for the incident owner",
				"rotate password and reason immediately after first successful login because the identity enters CREDENTIAL_ROTATION_REQUIRED"
			);
		}
	}

	public record Seed(
		String roleProcedure,
		String accountProcedure
	) {

		static Seed defaults() {
			return new Seed(
				"migrate admin_role_permissions first, then assign admin_user_roles before RBAC enforcement",
				"bootstrap env admin and operator accounts until persistent admin_users seed is verified"
			);
		}
	}

	public record Rollback(String runbook) {

		static Rollback defaults() {
			return new Rollback(
				"disable rbac-enforcement and audit-enforcement, keep shadow logging, restore legacy env admin fallback, and redeploy the previous artifact"
			);
		}
	}

	public record ReleaseGate(
		BlockerMode blockerMode,
		List<String> blockers
	) {

		static ReleaseGate defaults() {
			return new ReleaseGate(
				BlockerMode.WARN,
				List.of(
					"RBAC shadow denials are untriaged",
					"audit shadow misses privileged admin action",
					"legacy env admin fallback removal criteria are incomplete",
					"break-glass credential rotation is overdue",
					"role or account seed is missing in prod"
				)
			);
		}
	}
}
