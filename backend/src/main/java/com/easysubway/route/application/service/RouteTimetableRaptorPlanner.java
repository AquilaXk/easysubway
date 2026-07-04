package com.easysubway.route.application.service;

import com.easysubway.route.application.port.in.RouteV2SearchUseCase.SearchRouteV2Command;
import com.easysubway.route.application.port.out.LoadRouteTimetablePort.RouteTimetable;
import com.easysubway.route.application.port.out.LoadRouteTimetablePort.ServiceCalendar;
import com.easysubway.route.application.port.out.LoadRouteTimetablePort.ServiceCalendarDate;
import com.easysubway.route.application.port.out.LoadRouteTimetablePort.TransitRoute;
import com.easysubway.route.application.port.out.LoadRouteTimetablePort.TransitStopTime;
import com.easysubway.route.application.port.out.LoadRouteTimetablePort.TransitTrip;
import com.easysubway.route.domain.BoardingSlackPolicy;
import com.easysubway.route.domain.EtaSource;
import com.easysubway.route.domain.RouteSearchResult;
import com.easysubway.route.domain.RouteSearchStatus;
import com.easysubway.route.domain.RouteStep;
import java.time.Duration;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

class RouteTimetableRaptorPlanner {

	private static final ZoneId SERVICE_ZONE = ZoneId.of("Asia/Seoul");
	private static final int SERVICE_DAY_CUTOFF_HOUR = 3;
	private static final int PARETO_LIMIT = 3;

	List<RouteSearchResult> search(SearchRouteV2Command command, RouteTimetable timetable) {
		ServiceDay serviceDay = serviceDay(command);
		Set<String> activeServiceIds = activeServiceIds(timetable, serviceDay.date());
		if (activeServiceIds.isEmpty()) {
			return List.of();
		}

		Map<String, TransitRoute> routesById = routesById(timetable);
		Map<String, List<TransitStopTime>> stopTimesByTrip = stopTimesByTrip(timetable);
		List<TransitTrip> trips = timetable.transitTrips().stream()
			.filter(trip -> activeServiceIds.contains(trip.serviceId()))
			.filter(trip -> stopTimesByTrip.getOrDefault(trip.id(), List.of()).size() > 1)
			.sorted(Comparator.comparing(TransitTrip::id))
			.toList();
		if (trips.isEmpty()) {
			return List.of();
		}

		Map<String, List<Label>> labels = new HashMap<>();
		labels.put(command.originStationId(), List.of(new Label(
			command.originStationId(),
			serviceDay.departureSeconds(),
			serviceDay.departureSeconds(),
			0,
			List.of()
		)));

		for (int round = 0; round <= command.maxTransfers(); round += 1) {
			for (TransitTrip trip : trips) {
				scanTrip(command, labels, trip, routesById.get(trip.routeId()), stopTimesByTrip.get(trip.id()), round);
			}
		}

		return labels.getOrDefault(command.destinationStationId(), List.of()).stream()
			.filter(label -> !label.path().isEmpty())
			.sorted(RouteTimetableRaptorPlanner::compareLabels)
			.limit(Math.min(command.alternativeCount(), PARETO_LIMIT))
			.map(label -> toRouteSearchResult(command, label, serviceDay))
			.toList();
	}

	private void scanTrip(
		SearchRouteV2Command command,
		Map<String, List<Label>> labels,
		TransitTrip trip,
		TransitRoute route,
		List<TransitStopTime> stopTimes,
		int round
	) {
		Boarding boarding = null;
		for (TransitStopTime stopTime : stopTimes) {
			for (Label label : List.copyOf(labels.getOrDefault(stopTime.stationId(), List.of()))) {
				if (canBoard(command, label, stopTime, round)) {
					boarding = betterBoarding(boarding, label, stopTime);
				}
			}
			if (boarding == null || stopTime.stopSequence() <= boarding.stopTime().stopSequence()) {
				continue;
			}
			addLabel(labels, new Label(
				stopTime.stationId(),
				stopTime.arrivalSeconds(),
				boarding.label().startSeconds(),
				boarding.label().boardings() + 1,
				withLeg(boarding.label().path(), new RideLeg(trip, route, boarding.stopTime(), stopTime))
			));
		}
	}

	private boolean canBoard(SearchRouteV2Command command, Label label, TransitStopTime stopTime, int round) {
		int slackSeconds = BoardingSlackPolicy.secondsFor(command.mobilityType());
		return label.boardings() == round && stopTime.departureSeconds() >= label.timeSeconds() + slackSeconds;
	}

	private Boarding betterBoarding(Boarding current, Label label, TransitStopTime stopTime) {
		if (current == null || label.timeSeconds() < current.label().timeSeconds()) {
			return new Boarding(label, stopTime);
		}
		return current;
	}

	private void addLabel(Map<String, List<Label>> labels, Label candidate) {
		List<Label> stationLabels = labels.getOrDefault(candidate.stationId(), List.of());
		if (stationLabels.stream().anyMatch(existing -> sameLabel(existing, candidate) || dominates(existing, candidate))) {
			return;
		}
		List<Label> kept = new ArrayList<>();
		for (Label existing : stationLabels) {
			if (!dominates(candidate, existing)) {
				kept.add(existing);
			}
		}
		kept.add(candidate);
		kept.sort(RouteTimetableRaptorPlanner::compareLabels);
		labels.put(candidate.stationId(), List.copyOf(kept.stream().limit(PARETO_LIMIT).toList()));
	}

	private static boolean dominates(Label left, Label right) {
		return left.timeSeconds() <= right.timeSeconds()
			&& left.boardings() <= right.boardings()
			&& (left.timeSeconds() < right.timeSeconds() || left.boardings() < right.boardings());
	}

	private static boolean sameLabel(Label left, Label right) {
		return left.timeSeconds() == right.timeSeconds()
			&& left.boardings() == right.boardings()
			&& left.path().stream().map(RideLeg::tripId).toList().equals(right.path().stream().map(RideLeg::tripId).toList());
	}

	private static int compareLabels(Label left, Label right) {
		return Comparator.comparingInt(Label::timeSeconds)
			.thenComparingInt(Label::boardings)
			.thenComparingInt(label -> label.path().size())
			.compare(left, right);
	}

	private static List<RideLeg> withLeg(List<RideLeg> path, RideLeg leg) {
		List<RideLeg> next = new ArrayList<>(path);
		next.add(leg);
		return List.copyOf(next);
	}

	private static RouteSearchResult toRouteSearchResult(SearchRouteV2Command command, Label label, ServiceDay serviceDay) {
		List<RouteStep> steps = new ArrayList<>();
		int sequence = 1;
		for (RideLeg leg : label.path()) {
			String lineName = leg.lineName();
			steps.add(new RouteStep(
				sequence,
				"ride",
				lineName + " 승차",
				leg.from().stationId() + "에서 " + leg.to().stationId() + "까지 시간표 기준으로 이동",
				leg.lineId(),
				lineName,
				leg.from().stationId(),
				leg.to().stationId(),
				Math.max(1, (int) Math.ceil((leg.to().arrivalSeconds() - leg.from().departureSeconds()) / 60.0)),
				0,
				false,
				"UNKNOWN",
				false,
				EtaSource.PLANNED.name(),
				"TIMETABLE",
				"시간표"
			));
			sequence += 1;
		}
		return new RouteSearchResult(
			"route-v2-raptor-" + serviceDay.date() + "-" + command.originStationId() + "-" + command.destinationStationId()
				+ "-" + label.timeSeconds(),
			command.originStationId(),
			command.originStationId(),
			command.destinationStationId(),
			command.destinationStationId(),
			command.mobilityType(),
			RouteSearchStatus.FOUND,
			label.path().getFirst().lineId(),
			label.path().getFirst().lineName(),
			Math.max(1, (label.timeSeconds() - label.startSeconds()) / 60),
			List.copyOf(steps),
			List.of(),
			List.of(),
			LocalDateTime.of(serviceDay.date(), java.time.LocalTime.MIDNIGHT).plusSeconds(label.startSeconds())
		);
	}

	private static Map<String, TransitRoute> routesById(RouteTimetable timetable) {
		Map<String, TransitRoute> routes = new HashMap<>();
		for (TransitRoute route : timetable.transitRoutes()) {
			routes.put(route.id(), route);
		}
		return routes;
	}

	private static Map<String, List<TransitStopTime>> stopTimesByTrip(RouteTimetable timetable) {
		Map<String, List<TransitStopTime>> stopTimes = new HashMap<>();
		for (TransitStopTime stopTime : timetable.transitStopTimes()) {
			stopTimes.computeIfAbsent(stopTime.tripId(), ignored -> new ArrayList<>()).add(stopTime);
		}
		for (Map.Entry<String, List<TransitStopTime>> entry : stopTimes.entrySet()) {
			entry.setValue(entry.getValue().stream()
				.sorted(Comparator.comparingInt(TransitStopTime::stopSequence))
				.toList());
		}
		return stopTimes;
	}

	private static Set<String> activeServiceIds(RouteTimetable timetable, LocalDate serviceDate) {
		Set<String> active = new HashSet<>();
		for (ServiceCalendar calendar : timetable.serviceCalendars()) {
			if (!serviceDate.isBefore(calendar.startDate())
				&& !serviceDate.isAfter(calendar.endDate())
				&& runsOn(calendar, serviceDate)) {
				active.add(calendar.serviceId());
			}
		}
		for (ServiceCalendarDate exception : timetable.serviceCalendarDates()) {
			if (!serviceDate.equals(exception.date())) {
				continue;
			}
			if (exception.exceptionType() == 1) {
				active.add(exception.serviceId());
			} else {
				active.remove(exception.serviceId());
			}
		}
		return active;
	}

	private static boolean runsOn(ServiceCalendar calendar, LocalDate serviceDate) {
		return switch (serviceDate.getDayOfWeek()) {
			case MONDAY -> calendar.monday();
			case TUESDAY -> calendar.tuesday();
			case WEDNESDAY -> calendar.wednesday();
			case THURSDAY -> calendar.thursday();
			case FRIDAY -> calendar.friday();
			case SATURDAY -> calendar.saturday();
			case SUNDAY -> calendar.sunday();
		};
	}

	private static ServiceDay serviceDay(SearchRouteV2Command command) {
		ZonedDateTime departure = command.departureTime().atZoneSameInstant(SERVICE_ZONE);
		LocalDate serviceDate = departure.toLocalDate();
		if (departure.getHour() < SERVICE_DAY_CUTOFF_HOUR) {
			serviceDate = serviceDate.minusDays(1);
		}
		int departureSeconds = Math.toIntExact(Duration.between(
			serviceDate.atStartOfDay(SERVICE_ZONE),
			departure
		).toSeconds());
		return new ServiceDay(serviceDate, departureSeconds);
	}

	private record ServiceDay(LocalDate date, int departureSeconds) {
	}

	private record Label(String stationId, int timeSeconds, int startSeconds, int boardings, List<RideLeg> path) {
	}

	private record Boarding(Label label, TransitStopTime stopTime) {
	}

	private record RideLeg(TransitTrip trip, TransitRoute route, TransitStopTime from, TransitStopTime to) {
		String tripId() {
			return trip.id();
		}

		String lineId() {
			return route == null ? from.lineId() : route.lineId();
		}

		String lineName() {
			if (route == null) {
				return from.lineId();
			}
			if (!route.routeLongName().isBlank()) {
				return route.routeLongName();
			}
			if (!route.routeShortName().isBlank()) {
				return route.routeShortName();
			}
			return route.lineId();
		}
	}
}
