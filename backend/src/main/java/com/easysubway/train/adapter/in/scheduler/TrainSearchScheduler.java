package com.easysubway.train.adapter.in.scheduler;

import com.easysubway.train.application.TrainSearchService;
import com.easysubway.train.application.TrainSearchService.TrainSearchFailure;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

@Component
class TrainSearchScheduler {

	private static final Logger log = LoggerFactory.getLogger(TrainSearchScheduler.class);

	private final TrainSearchService service;

	TrainSearchScheduler(TrainSearchService service) {
		this.service = service;
	}

	@Scheduled(
		cron = "${easysubway.train-search.catalog-refresh-cron:0 30 3 * * *}",
		zone = "Asia/Seoul"
	)
	void refreshCatalog() {
		try {
			service.refreshCatalog();
		} catch (TrainSearchFailure failure) {
			log.warn("train-search catalog refresh failed: code={}", failure.getCode());
		}
	}

	@Scheduled(
		cron = "${easysubway.train-search.cache-purge-cron:0 10 4 * * *}",
		zone = "Asia/Seoul"
	)
	void purgeExpiredCache() {
		int purged = service.purgeExpired();
		log.info("train-search expired cache purged: rows={}", purged);
	}
}
