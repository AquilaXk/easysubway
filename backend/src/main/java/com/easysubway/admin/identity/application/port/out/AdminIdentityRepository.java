package com.easysubway.admin.identity.application.port.out;

import com.easysubway.admin.identity.domain.AdminIdentity;
import com.easysubway.admin.identity.domain.AdminLoginAudit;
import java.util.Optional;

public interface AdminIdentityRepository {

	Optional<AdminIdentity> findByLoginId(String loginId);

	AdminIdentity save(AdminIdentity identity);

	AdminIdentity upsertBootstrap(AdminIdentity identity);

	void recordLoginAudit(AdminLoginAudit audit);
}
