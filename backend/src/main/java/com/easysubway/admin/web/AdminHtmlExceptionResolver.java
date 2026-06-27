package com.easysubway.admin.web;

import com.easysubway.common.error.ConflictException;
import com.easysubway.common.error.InvalidRequestException;
import com.easysubway.common.error.ResourceNotFoundException;
import com.easysubway.transit.domain.MasterDataWriteNotAllowedException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.Ordered;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.HandlerExceptionResolver;
import org.springframework.web.servlet.ModelAndView;

@Component
class AdminHtmlExceptionResolver implements HandlerExceptionResolver, Ordered {

	@Override
	public int getOrder() {
		return Ordered.HIGHEST_PRECEDENCE;
	}

	@Override
	public ModelAndView resolveException(
		HttpServletRequest request,
		HttpServletResponse response,
		Object handler,
		Exception exception
	) {
		if (!AdminHtmlRequest.matches(request)) {
			return null;
		}
		AdminHtmlError error = AdminHtmlError.from(exception);
		response.setStatus(error.status().value());
		ModelAndView view = new ModelAndView("admin/error");
		view.addObject("status", error.status().value());
		view.addObject("title", error.title());
		view.addObject("message", error.message());
		view.addObject("detail", error.detail());
		return view;
	}

	private record AdminHtmlError(HttpStatus status, String title, String message, String detail) {

		static AdminHtmlError from(Exception exception) {
			if (exception instanceof MasterDataWriteNotAllowedException) {
				return new AdminHtmlError(
					HttpStatus.LOCKED,
					"읽기 전용 마스터 데이터",
					"현재 운영 마스터 데이터는 저장할 수 없습니다.",
					exception.getMessage()
				);
			}
			if (exception instanceof ResourceNotFoundException) {
				return new AdminHtmlError(
					HttpStatus.NOT_FOUND,
					"대상을 찾을 수 없습니다",
					exception.getMessage(),
					"목록으로 돌아가 최신 상태를 다시 확인해 주세요."
				);
			}
			if (exception instanceof ConflictException) {
				return new AdminHtmlError(
					HttpStatus.CONFLICT,
					"요청이 최신 상태와 충돌했습니다",
					exception.getMessage(),
					"화면을 새로고침한 뒤 다시 시도해 주세요."
				);
			}
			if (exception instanceof InvalidRequestException
				|| exception instanceof MethodArgumentTypeMismatchException) {
				return new AdminHtmlError(
					HttpStatus.BAD_REQUEST,
					"입력값을 확인해야 합니다",
					exception.getMessage(),
					"입력한 값을 확인한 뒤 다시 제출해 주세요."
				);
			}
			return new AdminHtmlError(
				HttpStatus.INTERNAL_SERVER_ERROR,
				"요청을 처리하지 못했습니다",
				"관리자 요청 처리 중 오류가 발생했습니다.",
				"잠시 후 다시 시도하고, 문제가 반복되면 운영 로그를 확인해 주세요."
			);
		}
	}
}
