package com.easysubway.auth.adapter.out.security;

import com.easysubway.auth.application.port.out.RegisterAnonymousUserPort;
import com.easysubway.auth.domain.AnonymousUserCredentials;
import java.util.ArrayDeque;
import java.util.Deque;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.stereotype.Component;

@Component
public class SpringSecurityAnonymousUserRegistry implements RegisterAnonymousUserPort {

	static final int MAX_ANONYMOUS_USERS = 10_000;

	private final InMemoryUserDetailsManager userDetailsManager;
	private final PasswordEncoder passwordEncoder;
	private final int maxAnonymousUsers;
	private final Deque<String> issuedAnonymousUserIds = new ArrayDeque<>();

	@Autowired
	public SpringSecurityAnonymousUserRegistry(
		InMemoryUserDetailsManager userDetailsManager,
		PasswordEncoder passwordEncoder
	) {
		this(userDetailsManager, passwordEncoder, MAX_ANONYMOUS_USERS);
	}

	SpringSecurityAnonymousUserRegistry(
		InMemoryUserDetailsManager userDetailsManager,
		PasswordEncoder passwordEncoder,
		int maxAnonymousUsers
	) {
		this.userDetailsManager = userDetailsManager;
		this.passwordEncoder = passwordEncoder;
		this.maxAnonymousUsers = maxAnonymousUsers;
	}

	@Override
	public synchronized boolean existsByUserId(String userId) {
		return userDetailsManager.userExists(userId);
	}

	@Override
	public synchronized void registerAnonymousUser(AnonymousUserCredentials credentials) {
		// Spring Security에는 인코딩된 비밀번호만 등록하고, 평문은 발급 응답에서만 1회 노출한다.
		userDetailsManager.createUser(User.withUsername(credentials.userId())
			.password(passwordEncoder.encode(credentials.password()))
			.roles("USER")
			.build());
		issuedAnonymousUserIds.addLast(credentials.userId());
		evictOldestAnonymousUsers();
	}

	private void evictOldestAnonymousUsers() {
		// 공개 발급 API가 프로세스 메모리에 익명 계정을 무한히 쌓지 않게 런타임 발급분만 정리한다.
		while (issuedAnonymousUserIds.size() > maxAnonymousUsers) {
			String oldestUserId = issuedAnonymousUserIds.removeFirst();
			if (userDetailsManager.userExists(oldestUserId)) {
				userDetailsManager.deleteUser(oldestUserId);
			}
		}
	}
}
