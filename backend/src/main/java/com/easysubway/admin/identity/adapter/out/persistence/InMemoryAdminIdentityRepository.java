package com.easysubway.admin.identity.adapter.out.persistence;

import com.easysubway.admin.identity.application.port.out.AdminIdentityRepository;
import com.easysubway.admin.identity.domain.AdminIdentity;
import com.easysubway.admin.identity.domain.AdminLoginAudit;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Repository;

@Repository
@Profile("!prod")
public class InMemoryAdminIdentityRepository implements AdminIdentityRepository {

	private final ConcurrentMap<String, AdminIdentity> identitiesByLoginId = new ConcurrentHashMap<>();
	private final List<AdminLoginAudit> audits = new ArrayList<>();

	@Override
	public Optional<AdminIdentity> findByLoginId(String loginId) {
		return Optional.ofNullable(identitiesByLoginId.get(normalize(loginId)));
	}

	@Override
	public AdminIdentity save(AdminIdentity identity) {
		identitiesByLoginId.put(normalize(identity.loginId()), identity);
		return identity;
	}

	@Override
	public AdminIdentity upsertBootstrap(AdminIdentity identity) {
		return identitiesByLoginId.compute(normalize(identity.loginId()), (key, current) -> current == null ? identity : current);
	}

	@Override
	public synchronized void recordLoginAudit(AdminLoginAudit audit) {
		audits.add(audit);
	}

	public synchronized List<AdminLoginAudit> audits() {
		return List.copyOf(audits);
	}

	private static String normalize(String loginId) {
		return loginId == null ? "" : loginId.trim().toLowerCase(Locale.ROOT);
	}
}
