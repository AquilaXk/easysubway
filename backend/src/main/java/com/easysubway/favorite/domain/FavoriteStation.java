package com.easysubway.favorite.domain;

import java.time.LocalDateTime;

public record FavoriteStation(
	String userId,
	String stationId,
	LocalDateTime addedAt
) {
}
