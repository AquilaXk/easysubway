package com.easysubway.admin.web;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ModelAttribute;

@ControllerAdvice(annotations = Controller.class)
class AdminCommandTokenModelAdvice {

	private final AdminCommandTokenService commandTokenService;

	AdminCommandTokenModelAdvice(AdminCommandTokenService commandTokenService) {
		this.commandTokenService = commandTokenService;
	}

	@ModelAttribute
	void exposeAdminCommandToken(HttpServletRequest request, Model model) {
		if (isAdminHtmlPage(request)) {
			model.addAttribute(AdminCommandTokenService.PARAMETER_NAME, commandTokenService.issue(request));
		}
	}

	private static boolean isAdminHtmlPage(HttpServletRequest request) {
		String uri = request.getRequestURI();
		return AdminHtmlRequest.matches(request)
			&& !uri.startsWith("/admin/error")
			&& !uri.equals("/admin/login");
	}
}
