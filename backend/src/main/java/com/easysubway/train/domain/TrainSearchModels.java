package com.easysubway.train.domain;

import java.time.LocalDate;
import java.time.OffsetDateTime;

public final class TrainSearchModels {

	private TrainSearchModels() {}

	public record Station(String id, String name) {}

	public record TrainType(String code, String name, String providerCode) {
		public TrainType(String code, String name) {
			this(code, name, null);
		}
	}

	public record LegQuery(
		String departureStationId,
		String arrivalStationId,
		LocalDate departureDate,
		String trainType,
		String providerTrainGradeCode
	) {
		public LegQuery(
			String departureStationId,
			String arrivalStationId,
			LocalDate departureDate,
			String trainType
		) {
			this(departureStationId, arrivalStationId, departureDate, trainType, null);
		}
	}

	public record SearchCriteria(
		String departureStationId,
		String arrivalStationId,
		LocalDate departureDate,
		LocalDate returnDate,
		String trainType
	) {}

	public record SearchResult(
		OffsetDateTime observedAt,
		java.util.List<Journey> outbound,
		java.util.List<Journey> inbound
	) {}

	public record Journey(
		String trainNumber,
		String trainType,
		String departureStationId,
		String departureStationName,
		OffsetDateTime departureAt,
		String arrivalStationId,
		String arrivalStationName,
		OffsetDateTime arrivalAt,
		int durationMinutes,
		int adultFareWon
	) {}
}
