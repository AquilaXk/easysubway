package com.easysubway.favorite.application.port.out;

import java.util.List;

public interface LoadFavoriteFacilityAlertTargetPort {

	List<String> loadUserIdsByFavoriteFacilityId(String facilityId);
}
