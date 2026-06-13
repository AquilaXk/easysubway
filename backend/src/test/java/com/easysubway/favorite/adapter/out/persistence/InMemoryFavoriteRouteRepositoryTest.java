package com.easysubway.favorite.adapter.out.persistence;

import static org.assertj.core.api.Assertions.assertThat;

import com.easysubway.favorite.domain.FavoriteRoute;
import java.time.LocalDateTime;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

@DisplayName("즐겨찾기 경로 인메모리 저장소")
class InMemoryFavoriteRouteRepositoryTest {

	@Test
	@DisplayName("사용자별 즐겨찾기 경로는 보관 한도를 넘기면 가장 오래된 항목부터 정리한다")
	void saveFavoriteRouteEvictsOldestRouteWhenLimitExceeded() {
		var repository = new InMemoryFavoriteRouteRepository();

		for (int index = 0; index <= InMemoryFavoriteRouteRepository.MAX_FAVORITE_ROUTES_PER_USER; index++) {
			repository.saveFavoriteRoute(new FavoriteRoute(
				"anonymous-user-1",
				"route-search-" + index,
				LocalDateTime.of(2026, 6, 13, 9, 0).plusMinutes(index)
			));
		}

		assertThat(repository.loadFavoriteRoutes("anonymous-user-1"))
			.hasSize(InMemoryFavoriteRouteRepository.MAX_FAVORITE_ROUTES_PER_USER)
			.extracting(FavoriteRoute::routeSearchId)
			.doesNotContain("route-search-0")
			.contains("route-search-1", "route-search-" + InMemoryFavoriteRouteRepository.MAX_FAVORITE_ROUTES_PER_USER);
	}
}
