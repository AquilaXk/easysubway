package com.easysubway.realtime.adapter.out.persistence;

import com.easysubway.realtime.application.port.out.RealtimeArrivalArchivePort;
import com.easysubway.realtime.application.port.out.RealtimeProviderCallQuotaPort;
import com.easysubway.realtime.domain.RealtimeArrivalObservation;
import java.time.Instant;
import java.time.ZoneId;
import java.util.List;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Repository;

@Repository
@Profile({"default", "dev", "test"})
public class DevelopmentRealtimeSafetyPorts implements RealtimeArrivalArchivePort, RealtimeProviderCallQuotaPort {
	private long windowMinute = Long.MIN_VALUE;
	private long windowDay = Long.MIN_VALUE;
	private int minuteCalls;
	private int dailyCalls;

	@Override
	public void saveAll(List<RealtimeArrivalObservation> observations) {
		// 로컬·테스트 profile은 운영 archive를 생성하지 않는다.
	}

	@Override
	public synchronized boolean tryAcquire(
		String providerId,
		Instant now,
		ZoneId providerZone,
		int limitPerMinute,
		int limitPerDay
	) {
		long minute = now.getEpochSecond() / 60;
		long day = now.atZone(providerZone).toLocalDate().toEpochDay();
		if (minute != windowMinute) {
			windowMinute = minute;
			minuteCalls = 0;
		}
		if (day != windowDay) {
			windowDay = day;
			dailyCalls = 0;
		}
		if (minuteCalls >= limitPerMinute || dailyCalls >= limitPerDay) {
			return false;
		}
		minuteCalls += 1;
		dailyCalls += 1;
		return true;
	}
}
