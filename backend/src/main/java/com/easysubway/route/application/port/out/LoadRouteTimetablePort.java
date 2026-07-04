package com.easysubway.route.application.port.out;

import java.util.List;

public interface LoadRouteTimetablePort {

	RouteTimetable loadRouteTimetable();

	record RouteTimetable(
		List<ServiceCalendar> serviceCalendars,
		List<ServiceCalendarDate> serviceCalendarDates,
		List<TransitRoute> transitRoutes,
		List<TransitTrip> transitTrips,
		List<TransitStopTime> transitStopTimes,
		List<TransitFrequency> transitFrequencies
	) {
		public static RouteTimetable empty() {
			return new RouteTimetable(List.of(), List.of(), List.of(), List.of(), List.of(), List.of());
		}
	}

	record ServiceCalendar(
		String serviceId,
		boolean monday,
		boolean tuesday,
		boolean wednesday,
		boolean thursday,
		boolean friday,
		boolean saturday,
		boolean sunday,
		String startDate,
		String endDate,
		String timezone
	) {
	}

	record ServiceCalendarDate(String serviceId, String date, int exceptionType) {
	}

	record TransitRoute(
		String id,
		String lineId,
		String routeShortName,
		String routeLongName,
		String directionName,
		String timezone
	) {
	}

	record TransitTrip(
		String id,
		String routeId,
		String serviceId,
		String tripHeadsign,
		String directionId,
		String servicePattern,
		int serviceDayStartSeconds
	) {
	}

	record TransitStopTime(
		String tripId,
		int stopSequence,
		String stationId,
		String lineId,
		int arrivalSeconds,
		int departureSeconds,
		int pickupType,
		int dropOffType
	) {
	}

	record TransitFrequency(
		String tripId,
		int startTimeSeconds,
		int endTimeSeconds,
		int headwaySeconds,
		boolean exactTimes
	) {
	}
}
