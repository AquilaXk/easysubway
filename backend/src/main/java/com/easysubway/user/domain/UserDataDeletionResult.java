package com.easysubway.user.domain;

public record UserDataDeletionResult(
	String userId,
	int deletedFavoriteStationCount,
	int deletedFavoriteFacilityCount,
	int deletedFavoriteRouteCount,
	boolean notificationSettingsDeleted,
	int deletedRegisteredDeviceCount,
	int deletedPushNotificationCount,
	boolean mobilityProfileDeleted,
	int anonymizedReportCount,
	boolean anonymousCredentialsDeleted
) {
}
