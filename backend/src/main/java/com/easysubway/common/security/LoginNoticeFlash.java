package com.easysubway.common.security;

import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import java.io.IOException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.authentication.AuthenticationFailureHandler;

public final class LoginNoticeFlash implements AuthenticationFailureHandler {

	private static final String SESSION_ATTRIBUTE = LoginNoticeFlash.class.getName() + ".notice";

	@Override
	public void onAuthenticationFailure(
		HttpServletRequest request,
		HttpServletResponse response,
		AuthenticationException exception
	) throws IOException, ServletException {
		request.getSession().setAttribute(SESSION_ATTRIBUTE, LoginNotice.RETRY_WARNING);
		String requestPath = request.getRequestURI().substring(request.getContextPath().length());
		String loginPath = "/operator/login".equals(requestPath) ? "/operator/login" : "/admin/login";
		response.sendRedirect(request.getContextPath() + loginPath);
	}

	public LoginNotice consume(HttpServletRequest request) {
		HttpSession session = request.getSession(false);
		if (session == null) {
			return LoginNotice.NONE;
		}
		Object notice = session.getAttribute(SESSION_ATTRIBUTE);
		session.removeAttribute(SESSION_ATTRIBUTE);
		return notice == LoginNotice.RETRY_WARNING ? LoginNotice.RETRY_WARNING : LoginNotice.NONE;
	}
}
