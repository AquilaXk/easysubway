package com.easysubway.favorite.application.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.easysubway.favorite.adapter.out.persistence.InMemoryFavoriteStationRepository;
import com.easysubway.favorite.application.port.in.RemoveFavoriteStationCommand;
import com.easysubway.favorite.application.port.in.SaveFavoriteStationCommand;
import com.easysubway.favorite.domain.InvalidFavoriteStationException;
import com.easysubway.transit.adapter.out.persistence.InMemoryTransitMasterRepository;
import com.easysubway.transit.domain.StationNotFoundException;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import org.junit.jupiter.api.Test;

class FavoriteStationServiceTest {

	private final InMemoryFavoriteStationRepository favoriteStationRepository =
		new InMemoryFavoriteStationRepository();
	private final FavoriteStationService service = new FavoriteStationService(
		favoriteStationRepository,
		favoriteStationRepository,
		favoriteStationRepository,
		new InMemoryTransitMasterRepository(),
		Clock.fixed(Instant.parse("2026-06-12T00:00:00Z"), ZoneId.of("Asia/Seoul"))
	);

	@Test
	void saveFavoriteStationStoresActiveStationOnce() {
		var favorite = service.saveFavoriteStation(new SaveFavoriteStationCommand(
			"anonymous-user-1",
			"station-sangnoksu"
		));
		var duplicated = service.saveFavoriteStation(new SaveFavoriteStationCommand(
			"anonymous-user-1",
			"station-sangnoksu"
		));

		assertThat(favorite.favoriteStation().userId()).isEqualTo("anonymous-user-1");
		assertThat(favorite.favoriteStation().stationId()).isEqualTo("station-sangnoksu");
		assertThat(favorite.favoriteStation().addedAt()).isEqualTo(LocalDateTime.of(2026, 6, 12, 9, 0));
		assertThat(favorite.station().station().nameKo()).isEqualTo("상록수");
		assertThat(duplicated).isEqualTo(favorite);
		assertThat(service.listFavoriteStations("anonymous-user-1")).containsExactly(favorite);
	}

	@Test
	void removeFavoriteStationDeletesOnlyRequestedStation() {
		service.saveFavoriteStation(new SaveFavoriteStationCommand("anonymous-user-1", "station-sangnoksu"));
		service.saveFavoriteStation(new SaveFavoriteStationCommand("anonymous-user-1", "station-sadang"));

		service.removeFavoriteStation(new RemoveFavoriteStationCommand("anonymous-user-1", "station-sangnoksu"));

		assertThat(service.listFavoriteStations("anonymous-user-1"))
			.extracting(favorite -> favorite.favoriteStation().stationId())
			.containsExactly("station-sadang");
	}

	@Test
	void saveFavoriteStationRequiresExistingActiveStation() {
		assertThatThrownBy(() -> service.saveFavoriteStation(new SaveFavoriteStationCommand(
			"anonymous-user-1",
			"missing-station"
		)))
			.isInstanceOf(StationNotFoundException.class)
			.hasMessage("역 정보를 찾을 수 없습니다.");
	}

	@Test
	void favoriteStationCommandsRequireUserAndStation() {
		assertThatThrownBy(() -> service.listFavoriteStations(""))
			.isInstanceOf(InvalidFavoriteStationException.class)
			.hasMessage("사용자 식별자가 필요합니다.");

		assertThatThrownBy(() -> service.saveFavoriteStation(new SaveFavoriteStationCommand(
			"anonymous-user-1",
			""
		)))
			.isInstanceOf(InvalidFavoriteStationException.class)
			.hasMessage("역 식별자가 필요합니다.");
	}
}
