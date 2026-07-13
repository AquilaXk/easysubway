package com.easysubway.realtime.application.port.out;

import com.easysubway.realtime.domain.RealtimeArrivalObservation;
import java.util.List;

@FunctionalInterface
public interface RealtimeArrivalArchivePort {

	RealtimeArrivalArchivePort NO_OP = (observations) -> { };

	void saveAll(List<RealtimeArrivalObservation> observations);
}
