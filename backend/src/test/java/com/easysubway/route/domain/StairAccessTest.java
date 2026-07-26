package com.easysubway.route.domain;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.profile.domain.MobilityType;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

@DisplayName("계단 접근성 판정 단일 원천")
class StairAccessTest {

	@Nested
	@DisplayName("스텝 판정")
	class StepJudgment {

		@Test
		@DisplayName("승차 스텝은 계단 개념이 적용되지 않아 NOT_APPLICABLE이다")
		void rideStepIsNotApplicable() {
			assertThat(StairAccess.ofStep(rideStep())).isEqualTo(StairAccess.NOT_APPLICABLE);
		}

		@Test
		@DisplayName("승차 스텝의 stairAccessState=UNKNOWN은 미확인이 아니라 판정 대상 밖이다")
		void rideStepUnknownStateIsNotAnUnverifiedSignal() {
			RouteStep ride = rideStep();

			assertThat(ride.stairAccessState()).isEqualTo("UNKNOWN");
			assertThat(StairAccess.ofStep(ride).demotedIfUnverified(true)).isEqualTo(StairAccess.NOT_APPLICABLE);
		}

		@Test
		@DisplayName("계단이 있는 전이는 STAIR_ONLY다")
		void stairTransitionIsStairOnly() {
			assertThat(StairAccess.ofStep(transitionStep(true, true))).isEqualTo(StairAccess.STAIR_ONLY);
		}

		@Test
		@DisplayName("검증된 무단차 전이는 STEP_FREE다")
		void verifiedTransitionIsStepFree() {
			assertThat(StairAccess.ofStep(transitionStep(false, true))).isEqualTo(StairAccess.STEP_FREE);
		}

		@Test
		@DisplayName("미검증 전이는 UNKNOWN이다")
		void unverifiedTransitionIsUnknown() {
			assertThat(StairAccess.ofStep(transitionStep(false, false))).isEqualTo(StairAccess.UNKNOWN);
		}

		@Test
		@DisplayName("확인되지 않은 근거가 있으면 STEP_FREE를 UNKNOWN으로 내린다")
		void unverifiedEvidenceDemotesStepFree() {
			assertThat(StairAccess.ofStep(transitionStep(false, true)).demotedIfUnverified(true))
				.isEqualTo(StairAccess.UNKNOWN);
		}

		@Test
		@DisplayName("확인되지 않은 근거는 STAIR_ONLY를 흔들지 않는다")
		void unverifiedEvidenceKeepsStairOnly() {
			assertThat(StairAccess.ofStep(transitionStep(true, true)).demotedIfUnverified(true))
				.isEqualTo(StairAccess.STAIR_ONLY);
		}
	}

	@Nested
	@DisplayName("경로 판정")
	class ItineraryJudgment {

		@Test
		@DisplayName("승차 스텝만 있어도 무단차 판정을 막지 않는다")
		void rideOnlyItineraryIsStepFree() {
			assertThat(StairAccess.ofItinerary(itinerary(List.of(rideStep()), List.of())))
				.isEqualTo(StairAccess.STEP_FREE);
		}

		@Test
		@DisplayName("검증된 전이와 승차만 있으면 STEP_FREE다")
		void verifiedTransitionsWithRideAreStepFree() {
			List<RouteStep> steps = List.of(transitionStep(false, true), rideStep(), transitionStep(false, true));

			assertThat(StairAccess.ofItinerary(itinerary(steps, List.of()))).isEqualTo(StairAccess.STEP_FREE);
		}

		@Test
		@DisplayName("계단 전이가 하나라도 있으면 STAIR_ONLY다")
		void stairTransitionMakesItineraryStairOnly() {
			List<RouteStep> steps = List.of(transitionStep(true, true), rideStep());

			assertThat(StairAccess.ofItinerary(itinerary(steps, List.of()))).isEqualTo(StairAccess.STAIR_ONLY);
		}

		@Test
		@DisplayName("STAIR_ONLY_ACCESS 경고는 스텝에 계단 표시가 없어도 STAIR_ONLY로 확정한다")
		void stairWarningMakesItineraryStairOnly() {
			List<RouteStep> steps = List.of(transitionStep(false, true), rideStep());
			List<RouteWarning> warnings = List.of(new RouteWarning(RouteWarningCode.STAIR_ONLY_ACCESS));

			assertThat(StairAccess.ofItinerary(itinerary(steps, warnings))).isEqualTo(StairAccess.STAIR_ONLY);
		}

		@Test
		@DisplayName("미검증 전이가 있으면 UNKNOWN이다")
		void unverifiedTransitionMakesItineraryUnknown() {
			List<RouteStep> steps = List.of(transitionStep(false, false), rideStep());

			assertThat(StairAccess.ofItinerary(itinerary(steps, warningsOnly()))).isEqualTo(StairAccess.UNKNOWN);
		}

		@Test
		@DisplayName("데이터 신뢰도 경고는 #2560 태깅 술어를 흔들지 않는다")
		void dataConfidenceWarningsDoNotChangeTaggingPredicate() {
			List<RouteStep> steps = List.of(transitionStep(false, true), rideStep());

			assertThat(StairAccess.ofItinerary(itinerary(steps, warningsOnly()))).isEqualTo(StairAccess.STEP_FREE);
		}

		@Test
		@DisplayName("스텝 판정을 접은 결과는 경로 판정과 같다")
		void foldingStepJudgmentsMatchesItineraryJudgment() {
			List<RouteStep> steps = List.of(transitionStep(false, true), rideStep(), transitionStep(false, false));

			assertThat(StairAccess.ofStepJudgments(steps.stream().map(StairAccess::ofStep).toList()))
				.isEqualTo(StairAccess.ofItinerary(itinerary(steps, List.of())));
		}
	}

	private static List<RouteWarning> warningsOnly() {
		return List.of(
			new RouteWarning(RouteWarningCode.STALE_ACCESSIBILITY_DATA),
			new RouteWarning(RouteWarningCode.LOW_DATA_CONFIDENCE)
		);
	}

	private static RouteStep rideStep() {
		return new RouteStep(
			2, "ride", "2호선 승차", "시간표 기준 이동", "L2", "2호선", "S1", "S2",
			5, 0, false, "UNKNOWN", false,
			EtaSource.PLANNED.name(), "TIMETABLE", "시간표", List.of(), null, null, null, null
		);
	}

	private static RouteStep transitionStep(boolean includesStairs, boolean verified) {
		return new RouteStep(
			1, "entry", "2호선 접근 동선 확인", "승하차 접근성 확인", "L2", "2호선", "S1", "S1",
			2, 40, includesStairs,
			includesStairs ? "STAIR_ONLY" : verified ? "STEP_FREE" : "UNKNOWN",
			!verified,
			EtaSource.PLANNED.name(), "TIMETABLE", verified ? "검증됨" : "확인 필요",
			List.of(), null, null, null, null
		);
	}

	private static RouteSearchResult itinerary(List<RouteStep> steps, List<RouteWarning> warnings) {
		return new RouteSearchResult(
			"route-1", "S1", "출발역", "S2", "도착역", MobilityType.WHEELCHAIR, RouteSearchStatus.FOUND,
			"L2", "2호선", 10, steps, warnings, List.of(), LocalDateTime.of(2026, 7, 26, 9, 0)
		);
	}
}
