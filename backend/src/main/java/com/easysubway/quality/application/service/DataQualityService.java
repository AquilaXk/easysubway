package com.easysubway.quality.application.service;

import com.easysubway.quality.application.port.in.DataQualityUseCase;
import com.easysubway.quality.domain.DataQualitySummary;
import com.easysubway.transit.application.port.out.LoadTransitMasterPort;
import com.easysubway.transit.domain.AccessibilityFacility;
import com.easysubway.transit.domain.AccessibilityFacilityStatus;
import com.easysubway.transit.domain.DataConfidenceLevel;
import com.easysubway.transit.domain.DataQualityLevel;
import com.easysubway.transit.domain.Station;
import com.easysubway.transit.domain.StationExit;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import org.springframework.stereotype.Service;

@Service
public class DataQualityService implements DataQualityUseCase {

	private final LoadTransitMasterPort loadTransitMasterPort;

	public DataQualityService(LoadTransitMasterPort loadTransitMasterPort) {
		this.loadTransitMasterPort = loadTransitMasterPort;
	}

	@Override
	public DataQualitySummary summarizeDataQuality() {
		List<Station> stations = loadTransitMasterPort.loadStations();
		List<StationExit> exits = loadTransitMasterPort.loadStationExits();
		List<AccessibilityFacility> facilities = loadTransitMasterPort.loadAccessibilityFacilities();

		return new DataQualitySummary(
			stations.size(),
			exits.size(),
			facilities.size(),
			countStationQuality(stations),
			countExitConfidence(exits),
			countFacilityConfidence(facilities),
			countNeedsVerificationFacilities(facilities),
			countMissingStationVerificationDate(stations)
		);
	}

	private Map<DataQualityLevel, Long> countStationQuality(List<Station> stations) {
		var counts = emptyQualityCounts();
		for (Station station : stations) {
			counts.computeIfPresent(station.dataQualityLevel(), (level, count) -> count + 1);
		}
		return counts;
	}

	private Map<DataConfidenceLevel, Long> countExitConfidence(List<StationExit> exits) {
		var counts = emptyConfidenceCounts();
		for (StationExit exit : exits) {
			counts.computeIfPresent(exit.dataConfidence(), (level, count) -> count + 1);
		}
		return counts;
	}

	private Map<DataConfidenceLevel, Long> countFacilityConfidence(List<AccessibilityFacility> facilities) {
		var counts = emptyConfidenceCounts();
		for (AccessibilityFacility facility : facilities) {
			counts.computeIfPresent(facility.dataConfidence(), (level, count) -> count + 1);
		}
		return counts;
	}

	private long countNeedsVerificationFacilities(List<AccessibilityFacility> facilities) {
		return facilities.stream()
			.filter(facility -> facility.dataConfidence() == DataConfidenceLevel.NEEDS_VERIFICATION
				|| facility.status() == AccessibilityFacilityStatus.UNKNOWN
				|| facility.status() == AccessibilityFacilityStatus.USER_REPORTED)
			.count();
	}

	private long countMissingStationVerificationDate(List<Station> stations) {
		return stations.stream()
			.filter(station -> station.lastVerifiedAt() == null)
			.count();
	}

	private EnumMap<DataQualityLevel, Long> emptyQualityCounts() {
		var counts = new EnumMap<DataQualityLevel, Long>(DataQualityLevel.class);
		for (DataQualityLevel level : DataQualityLevel.values()) {
			counts.put(level, 0L);
		}
		return counts;
	}

	private EnumMap<DataConfidenceLevel, Long> emptyConfidenceCounts() {
		var counts = new EnumMap<DataConfidenceLevel, Long>(DataConfidenceLevel.class);
		for (DataConfidenceLevel level : DataConfidenceLevel.values()) {
			counts.put(level, 0L);
		}
		return counts;
	}
}
