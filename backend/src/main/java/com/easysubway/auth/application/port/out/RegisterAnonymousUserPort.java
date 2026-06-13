package com.easysubway.auth.application.port.out;

import com.easysubway.auth.domain.AnonymousUserCredentials;

public interface RegisterAnonymousUserPort {

	boolean existsByUserId(String userId);

	void registerAnonymousUser(AnonymousUserCredentials credentials);
}
