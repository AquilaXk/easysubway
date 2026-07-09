package com.easysubway.operator.adapter.in.web;

import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
class OperatorRepeatedBrokenFacilitiesPageController {

	private final OperatorRepeatedBrokenFacilitiesAssembler repeatedBrokenFacilitiesAssembler;

	OperatorRepeatedBrokenFacilitiesPageController(
		OperatorRepeatedBrokenFacilitiesAssembler repeatedBrokenFacilitiesAssembler
	) {
		this.repeatedBrokenFacilitiesAssembler = repeatedBrokenFacilitiesAssembler;
	}

	@GetMapping("/operator/repeated-broken-facilities/page")
	String repeatedBrokenFacilitiesPage(
		@RequestParam(required = false) String q,
		@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
		@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
		@RequestParam(required = false) String sort,
		@RequestParam(required = false) String direction,
		Model model
	) {
		OperatorReportQuery query = OperatorReportQuery.of(q, from, to, sort, direction);
		model.addAttribute("query", query);
		model.addAttribute("report", repeatedBrokenFacilitiesAssembler.assemble(query));
		return "operator/repeated-broken-facilities";
	}
}
