package com.easysubway.common.security;

import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.security.web.authentication.LoginUrlAuthenticationEntryPoint;

final class HtmxRefreshAuthenticationEntryPoint implements AuthenticationEntryPoint {

	private static final String HX_REQUEST = "HX-Request";
	private static final String HX_REFRESH = "HX-Refresh";

	private final LoginUrlAuthenticationEntryPoint delegate;

	HtmxRefreshAuthenticationEntryPoint(String loginFormUrl) {
		this.delegate = new LoginUrlAuthenticationEntryPoint(loginFormUrl);
	}

	@Override
	public void commence(
		HttpServletRequest request,
		HttpServletResponse response,
		AuthenticationException authException
	) throws IOException, ServletException {
		response.setHeader(HX_REFRESH, "true");
		delegate.commence(request, response, authException);
	}

	static boolean matches(HttpServletRequest request) {
		return "true".equalsIgnoreCase(request.getHeader(HX_REQUEST));
	}
}
