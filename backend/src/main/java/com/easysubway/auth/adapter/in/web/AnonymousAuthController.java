package com.easysubway.auth.adapter.in.web;

import com.easysubway.auth.application.port.in.AnonymousAuthUseCase;
import com.easysubway.auth.domain.AnonymousUserCredentials;
import com.easysubway.auth.domain.AuthenticatedUser;
import com.easysubway.common.web.ApiResponse;
import java.security.Principal;
import java.time.LocalDateTime;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
class AnonymousAuthController {

	private final AnonymousAuthUseCase anonymousAuthUseCase;

	AnonymousAuthController(AnonymousAuthUseCase anonymousAuthUseCase) {
		this.anonymousAuthUseCase = anonymousAuthUseCase;
	}

	@PostMapping("/api/v1/auth/anonymous")
	ApiResponse<AnonymousAuthResponse> issueAnonymousUser() {
		return ApiResponse.ok(AnonymousAuthResponse.from(anonymousAuthUseCase.issueAnonymousUser()));
	}

	@GetMapping("/api/v1/me")
	ApiResponse<AuthenticatedUserResponse> currentUser(Principal principal) {
		return ApiResponse.ok(AuthenticatedUserResponse.from(anonymousAuthUseCase.currentUser(principal.getName())));
	}

	record AnonymousAuthResponse(
		String userId,
		String password,
		String authType,
		boolean anonymous,
		LocalDateTime createdAt
	) {

		static AnonymousAuthResponse from(AnonymousUserCredentials credentials) {
			return new AnonymousAuthResponse(
				credentials.userId(),
				credentials.password(),
				"BASIC",
				true,
				credentials.createdAt()
			);
		}
	}

	record AuthenticatedUserResponse(
		String userId,
		String authType,
		boolean anonymous
	) {

		static AuthenticatedUserResponse from(AuthenticatedUser user) {
			return new AuthenticatedUserResponse(
				user.userId(),
				user.authType(),
				user.anonymous()
			);
		}
	}
}
