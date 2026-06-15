package com.easysubway.user.application.port.in;

import com.easysubway.user.domain.UserDataDeletionResult;

public interface UserDataDeletionUseCase {

	UserDataDeletionResult deleteUserData(String userId);
}
