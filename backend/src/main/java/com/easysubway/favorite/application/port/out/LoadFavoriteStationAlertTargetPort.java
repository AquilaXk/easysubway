package com.easysubway.favorite.application.port.out;

import java.util.List;

public interface LoadFavoriteStationAlertTargetPort {

	List<String> loadUserIdsByFavoriteStationId(String stationId);
}
