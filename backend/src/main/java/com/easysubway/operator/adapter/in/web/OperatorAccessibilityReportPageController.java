package com.easysubway.operator.adapter.in.web;

import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
class OperatorAccessibilityReportPageController {

	private final OperatorAccessibilityReportAssembler reportAssembler;

	OperatorAccessibilityReportPageController(OperatorAccessibilityReportAssembler reportAssembler) {
		this.reportAssembler = reportAssembler;
	}

	@GetMapping("/operator/accessibility-report/page")
	String accessibilityReportPage(
		@RequestParam(required = false) String q,
		@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
		@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
		@RequestParam(required = false) String sort,
		@RequestParam(required = false) String direction,
		Model model
	) {
		OperatorReportQuery query = OperatorReportQuery.of(q, from, to, sort, direction);
		model.addAttribute("query", query);
		model.addAttribute("report", reportAssembler.assemble(query));
		return "operator/accessibility-report";
	}
}
