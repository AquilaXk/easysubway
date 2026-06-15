package com.easysubway.user.application.port.out;

public interface DeleteUserNotificationPreferencePort {

	boolean deleteNotificationSettings(String userId);

	int deleteRegisteredDevices(String userId);
}
