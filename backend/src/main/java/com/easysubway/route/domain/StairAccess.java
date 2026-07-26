package com.easysubway.route.domain;

import java.util.List;

/**
 * 계단 접근성 판정의 단일 원천(#2590).
 *
 * <p>{@link RouteStep#stairAccessState()}는 판정 결과가 아니라 원자료다. 기본 파생에
 * {@code STEP_FREE} 분기가 없어 계단 신호가 하나도 없는 승차 구간까지 {@code UNKNOWN}으로
 * 적힌다. 그 값을 표시 계층이 다시 판정하면 "확인해 봤더니 미상"과 "애초에 계단 개념이
 * 없음"이 한 토큰으로 뭉개진다. 판정은 여기서만 하고 결과를 응답에 실어 보낸다.
 *
 * <p><b>leg 판정과 경로 판정의 관계</b> — 경로 판정은 leg 판정을 접어 올린 값에,
 * 어느 leg에도 매달 수 없는 경로 단위 신호({@link #ofWarnings(List)})를 겹친 것이다.
 * 겹치는 연산이 {@link #merge(StairAccess)}와 {@link #demotedIfUnverified(boolean)}뿐이고
 * 둘 다 신중함을 낮추지 않으므로, <b>경로 판정은 leg 판정을 접은 값보다 결코 덜 신중하지
 * 않다.</b> 반대로 완전한 일치는 성립하지 않는다 — 계단 개념이 적용되지 않는 구간은
 * 미확인이 될 수 없어(정의상 {@link #NOT_APPLICABLE}) 경로 단위 신뢰도 경고를 대신
 * 짊어질 leg가 없기 때문이다. 표시 계층이 leg를 접어 경로 판정을 복원하는 것은 판정
 * 필드가 없는 응답에서의 폴백일 뿐이며, 그 폴백이 경로 판정보다 강하게 단언할 수 있는
 * 경우는 "계단 장벽을 질 수 있는 leg가 하나도 없는 경로"뿐이다.
 */
public enum StairAccess {

	/**
	 * 계단 개념이 적용되지 않는 구간. 승차 구간에는 오르내릴 계단 자체가 없으므로 미확인이
	 * 아니다. 경로 판정에 기여하지 않는다.
	 */
	NOT_APPLICABLE(0),
	STEP_FREE(1),
	UNKNOWN(2),
	STAIR_ONLY(3);

	private static final String RIDE_STEP_TYPE = "ride";

	/**
	 * 정직 사다리에서의 신중함 등급. 값을 하나 추가할 때 선언 위치에 따라 판정이 조용히
	 * 뒤집히지 않도록 등급을 값에 못박는다.
	 */
	private final int caution;

	StairAccess(int caution) {
		this.caution = caution;
	}

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
			.merge(ofWarnings(itinerary.warnings()));
	}

	/**
	 * 스텝 판정들을 경로 판정으로 접는다. 모든 스텝이 {@link #NOT_APPLICABLE}이면 계단
	 * 장벽이 놓인 구간이 하나도 없다는 뜻이므로 {@link #STEP_FREE}로 확정한다.
	 */
	public static StairAccess ofStepJudgments(List<StairAccess> stepJudgments) {
		StairAccess merged = stepJudgments.stream().reduce(NOT_APPLICABLE, StairAccess::merge);
		return merged == NOT_APPLICABLE ? STEP_FREE : merged;
	}

	/**
	 * 경로 전체에 걸린 계단 경고. 특정 구간에 매달 수 없어 leg 판정이 담지 못하는 신호다.
	 */
	public static StairAccess ofWarnings(List<RouteWarning> warnings) {
		return warnings.stream().anyMatch(warning -> warning.code() == RouteWarningCode.STAIR_ONLY_ACCESS)
			? STAIR_ONLY
			: NOT_APPLICABLE;
	}

	/**
	 * 계단 사실이 아니라 "그 사실을 확인할 수 없었다"를 말하는 경고가 붙었는지.
	 *
	 * <p>분류를 {@code switch}로 두는 이유는 fail open을 막기 위해서다. {@link RouteWarningCode}에
	 * 값이 추가되면 이 exhaustive switch가 컴파일을 멈춰 분류를 강제한다. 카운터 필드를 읽는
	 * 방식이었다면 새 사유가 조용히 0으로 남아 무단차 단언을 통과시켰을 것이다.
	 */
	public static boolean hasUnverifiedEvidence(List<RouteWarning> warnings) {
		return warnings.stream().anyMatch(warning -> switch (warning.code()) {
			case LOW_DATA_CONFIDENCE, STALE_ACCESSIBILITY_DATA -> true;
			case STAIR_ONLY_ACCESS -> false;
		});
	}

	/**
	 * 확인되지 않은 근거가 붙은 구간을 무단차로 단언하지 않는다(정직 사다리). 계단 개념이
	 * 적용되지 않는 구간은 미확인이 될 수 없으므로 그대로 둔다.
	 */
	public StairAccess demotedIfUnverified(boolean unverifiedEvidence) {
		return this == STEP_FREE && unverifiedEvidence ? UNKNOWN : this;
	}

	/** 둘 중 더 신중한 판정. */
	public StairAccess merge(StairAccess other) {
		return caution >= other.caution ? this : other;
	}
}
