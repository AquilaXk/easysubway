package com.easysubway.favorite.application.port.out;

import java.util.List;

public interface LoadFavoriteRouteAlertTargetPort {

	List<String> loadUserIdsByRouteStationId(String stationId);
}
