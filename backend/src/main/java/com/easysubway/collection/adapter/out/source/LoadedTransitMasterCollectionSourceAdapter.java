package com.easysubway.collection.adapter.out.source;

import com.easysubway.collection.application.port.out.FetchTransitMasterCollectionSourcePort;
import com.easysubway.collection.application.port.out.TransitMasterCollectionSnapshot;
import com.easysubway.transit.application.port.out.LoadTransitMasterPort;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import org.springframework.stereotype.Component;

@Component
class LoadedTransitMasterCollectionSourceAdapter implements FetchTransitMasterCollectionSourcePort {

	private final LoadTransitMasterPort loadTransitMasterPort;

	LoadedTransitMasterCollectionSourceAdapter(LoadTransitMasterPort loadTransitMasterPort) {
		this.loadTransitMasterPort = loadTransitMasterPort;
	}

	@Override
	public TransitMasterCollectionSnapshot fetch() {
		int operators = loadTransitMasterPort.loadOperators().size();
		int lines = loadTransitMasterPort.loadLines().size();
		int stations = loadTransitMasterPort.loadStations().size();
		int stationLines = loadTransitMasterPort.loadStationLines().size();
		int exits = loadTransitMasterPort.loadStationExits().size();
		int facilities = loadTransitMasterPort.loadAccessibilityFacilities().size();
		String payload = "operators=%d;lines=%d;stations=%d;stationLines=%d;exits=%d;facilities=%d"
			.formatted(operators, lines, stations, stationLines, exits, facilities);
		return new TransitMasterCollectionSnapshot(
			"load-transit-master-port://official-current",
			"transit-master://loaded-current",
			sha256(payload),
			operators + lines + stations + stationLines + exits + facilities
		);
	}

	private static String sha256(String payload) {
		try {
			return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
				.digest(payload.getBytes(StandardCharsets.UTF_8)));
		} catch (NoSuchAlgorithmException exception) {
			throw new IllegalStateException("SHA-256 digest is unavailable.", exception);
		}
	}
}
