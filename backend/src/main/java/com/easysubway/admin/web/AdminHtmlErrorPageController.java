package com.easysubway.admin.web;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
class AdminHtmlErrorPageController {

	@GetMapping("/admin/error/page")
	String errorPage(HttpServletRequest request, Model model) {
		model.addAttribute("status", request.getAttribute("adminErrorStatus"));
		model.addAttribute("title", request.getAttribute("adminErrorTitle"));
		model.addAttribute("message", request.getAttribute("adminErrorMessage"));
		model.addAttribute("detail", request.getAttribute("adminErrorDetail"));
		return "admin/error";
	}
}
