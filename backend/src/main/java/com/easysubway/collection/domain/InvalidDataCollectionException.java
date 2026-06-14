package com.easysubway.collection.domain;

import com.easysubway.common.error.InvalidRequestException;

public class InvalidDataCollectionException extends InvalidRequestException {

	public InvalidDataCollectionException(String message) {
		super(message);
	}
}
