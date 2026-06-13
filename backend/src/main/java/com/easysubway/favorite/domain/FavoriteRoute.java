package com.easysubway.favorite.domain;

import java.time.LocalDateTime;

public record FavoriteRoute(
	String userId,
	String routeSearchId,
	LocalDateTime addedAt
) {

	public FavoriteRoute {
		if (userId == null || userId.isBlank()) {
			throw new InvalidFavoriteRouteException("사용자 식별자가 필요합니다.");
		}
		if (routeSearchId == null || routeSearchId.isBlank()) {
			throw new InvalidFavoriteRouteException("경로 검색 식별자가 필요합니다.");
		}
		if (addedAt == null) {
			throw new InvalidFavoriteRouteException("추가 시각이 필요합니다.");
		}
	}
}
