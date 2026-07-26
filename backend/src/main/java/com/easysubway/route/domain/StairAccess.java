package com.easysubway.route.domain;

import java.util.List;

/**
 * 계단 접근성 판정의 단일 원천(#2590).
 *
 * <p>{@link RouteStep#stairAccessState()}는 판정 결과가 아니라 원자료다. 기본 파생에
 * {@code STEP_FREE} 분기가 없어 계단 신호가 하나도 없는 승차 구간까지 {@code UNKNOWN}으로
 * 적힌다. 그 값을 표시 계층이 다시 판정하면 "확인해 봤더니 미상"과 "애초에 계단 개념이
 * 없음"이 한 토큰으로 뭉개진다. 판정은 여기서만 하고 결과를 응답에 실어 보낸다.
 */
public enum StairAccess {

	/**
	 * 계단 개념이 적용되지 않는 구간. 승차 구간에는 오르내릴 계단 자체가 없으므로 미확인이
	 * 아니다. 경로 판정에 기여하지 않는다.
	 */
	NOT_APPLICABLE,
	STEP_FREE,
	UNKNOWN,
	STAIR_ONLY;

	private static final String RIDE_STEP_TYPE = "ride";

	/**
	 * 스텝 하나의 계단 판정. 입력은 계단 사실뿐이다 — 데이터 신뢰도는 별도 축이라
	 * {@link #demotedIfUnverified(boolean)}가 맡는다.
	 */
	public static StairAccess ofStep(RouteStep step) {
		if (step.includesStairs()) {
			return STAIR_ONLY;
		}
		if (step.requiresAccessibilityCheck()) {
			return UNKNOWN;
		}
		return RIDE_STEP_TYPE.equals(step.stepType()) ? NOT_APPLICABLE : STEP_FREE;
	}

	/**
	 * 경로 전체의 계단 판정. #2560 무단차 대안 태깅이 쓰는 술어이므로 계단 사실만 본다 —
	 * 데이터 신뢰도 경고로 후보 집합이 흔들리면 안 된다.
	 */
	public static StairAccess ofItinerary(RouteSearchResult itinerary) {
		return ofStepJudgments(itinerary.steps().stream().map(StairAccess::ofStep).toList())
			.merge(stairWarning(itinerary.warnings()));
	}

	/**
	 * 스텝 판정들을 경로 판정으로 접는다. 모든 스텝이 {@link #NOT_APPLICABLE}이면 계단
	 * 장벽이 놓인 구간이 하나도 없다는 뜻이므로 {@link #STEP_FREE}로 확정한다.
	 */
	public static StairAccess ofStepJudgments(List<StairAccess> stepJudgments) {
		StairAccess merged = NOT_APPLICABLE;
		for (StairAccess judgment : stepJudgments) {
			merged = merged.merge(judgment);
		}
		return merged == NOT_APPLICABLE ? STEP_FREE : merged;
	}

	/**
	 * 확인되지 않은 근거가 붙은 구간을 무단차로 단언하지 않는다(정직 사다리). 계단 개념이
	 * 적용되지 않는 구간은 미확인이 될 수 없으므로 그대로 둔다.
	 */
	public StairAccess demotedIfUnverified(boolean unverifiedEvidence) {
		return this == STEP_FREE && unverifiedEvidence ? UNKNOWN : this;
	}

	public StairAccess merge(StairAccess other) {
		return compareTo(other) >= 0 ? this : other;
	}

	private static StairAccess stairWarning(List<RouteWarning> warnings) {
		return warnings.stream().anyMatch(warning -> warning.code() == RouteWarningCode.STAIR_ONLY_ACCESS)
			? STAIR_ONLY
			: NOT_APPLICABLE;
	}
}
