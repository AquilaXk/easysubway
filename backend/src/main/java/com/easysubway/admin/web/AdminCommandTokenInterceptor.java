package com.easysubway.admin.web;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

@Component
class AdminCommandTokenInterceptor implements HandlerInterceptor {

	private final AdminCommandTokenService commandTokenService;

	AdminCommandTokenInterceptor(AdminCommandTokenService commandTokenService) {
		this.commandTokenService = commandTokenService;
	}

	@Override
	public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
		if (!isAdminFormPost(request)) {
			return true;
		}
		String token = request.getParameter(AdminCommandTokenService.PARAMETER_NAME);
		if (token != null) {
			commandTokenService.consume(request, token);
		}
		return true;
	}

	private static boolean isAdminFormPost(HttpServletRequest request) {
		String uri = request.getRequestURI();
		String contentType = request.getContentType();
		return "POST".equals(request.getMethod())
			&& uri.startsWith("/admin/")
			&& !uri.equals("/admin/login")
			&& !uri.startsWith("/admin/error")
			&& contentType != null
			&& contentType.startsWith(MediaType.APPLICATION_FORM_URLENCODED_VALUE);
	}
}
