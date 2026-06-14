package com.easysubway.collection.application.service;

import com.easysubway.collection.application.port.out.SaveDataCollectionRunPort;
import com.easysubway.collection.domain.DataCollectionRun;
import com.easysubway.collection.domain.DataCollectionSource;
import com.easysubway.collection.domain.DataCollectionStatus;
import com.easysubway.transit.application.port.out.LoadTransitMasterPort;
import java.time.Clock;
import java.time.LocalDateTime;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

@Service
public class DataCollectionRunRecorder {

	private final LoadTransitMasterPort loadTransitMasterPort;
	private final SaveDataCollectionRunPort saveDataCollectionRunPort;
	private final Clock clock;

	@Autowired
	public DataCollectionRunRecorder(
		LoadTransitMasterPort loadTransitMasterPort,
		SaveDataCollectionRunPort saveDataCollectionRunPort
	) {
		this(loadTransitMasterPort, saveDataCollectionRunPort, Clock.systemDefaultZone());
	}

	public DataCollectionRunRecorder(
		LoadTransitMasterPort loadTransitMasterPort,
		SaveDataCollectionRunPort saveDataCollectionRunPort,
		Clock clock
	) {
		this.loadTransitMasterPort = loadTransitMasterPort;
		this.saveDataCollectionRunPort = saveDataCollectionRunPort;
		this.clock = clock;
	}

	public DataCollectionRun recordTransitMasterRun(String runId, String requestedBy) {
		LocalDateTime startedAt = LocalDateTime.now(clock);
		int collectedCount = countTransitMasterRecords();
		LocalDateTime completedAt = LocalDateTime.now(clock);
		var run = new DataCollectionRun(
			runId,
			DataCollectionSource.TRANSIT_MASTER,
			DataCollectionStatus.COMPLETED,
			requestedBy,
			startedAt,
			completedAt,
			collectedCount,
			null
		);
		return saveDataCollectionRunPort.saveRun(run);
	}

	private int countTransitMasterRecords() {
		// 외부 수집기를 붙이기 전에는 현재 마스터 데이터 로딩 경로가 읽히는지 실행 기록으로 검증한다.
		return loadTransitMasterPort.loadOperators().size()
			+ loadTransitMasterPort.loadLines().size()
			+ loadTransitMasterPort.loadStations().size()
			+ loadTransitMasterPort.loadStationLines().size()
			+ loadTransitMasterPort.loadStationExits().size()
			+ loadTransitMasterPort.loadAccessibilityFacilities().size();
	}
}
