package com.easysubway.transit.application.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.easysubway.transit.adapter.out.persistence.InMemoryTransitMasterRepository;
import com.easysubway.transit.application.port.in.StationSearchCommand;
import com.easysubway.transit.domain.DataQualityLevel;
import com.easysubway.transit.domain.StationNotFoundException;
import org.junit.jupiter.api.Test;

class TransitMasterServiceTest {

	private final TransitMasterService service = new TransitMasterService(new InMemoryTransitMasterRepository());

	@Test
	void listOperatorsReturnsActiveMasterData() {
		var operators = service.listOperators();

		assertThat(operators)
			.extracting("id")
			.contains("seoul-metro", "korail");
	}

	@Test
	void listLinesCanFilterByOperatorId() {
		var lines = service.listLines("korail");

		assertThat(lines)
			.extracting("id")
			.containsExactly("suin-bundang");
	}

	@Test
	void searchStationsMatchesKoreanAndEnglishNames() {
		var koreanMatches = service.searchStations(new StationSearchCommand("상록수", null));
		var englishMatches = service.searchStations(new StationSearchCommand("sang", null));

		assertThat(koreanMatches).hasSize(1);
		assertThat(englishMatches).hasSize(1);
		assertThat(koreanMatches.getFirst().station().dataQualityLevel()).isEqualTo(DataQualityLevel.LEVEL_1);
	}

	@Test
	void getStationThrowsDomainExceptionForUnknownStation() {
		assertThatThrownBy(() -> service.getStation("missing"))
			.isInstanceOf(StationNotFoundException.class)
			.hasMessage("역 정보를 찾을 수 없습니다.");
	}
}
