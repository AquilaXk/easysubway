package com.easysubway.route.adapter.out.persistence;

import com.easysubway.route.application.port.out.LoadRouteSearchPort;
import com.easysubway.route.application.port.out.SaveRouteSearchPort;
import com.easysubway.route.domain.RouteSearchResult;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import org.springframework.stereotype.Repository;

@Repository
public class InMemoryRouteSearchRepository implements LoadRouteSearchPort, SaveRouteSearchPort {

	private final Map<String, RouteSearchResult> routeSearches = new ConcurrentHashMap<>();

	@Override
	public Optional<RouteSearchResult> loadRouteSearch(String routeSearchId) {
		return Optional.ofNullable(routeSearches.get(routeSearchId));
	}

	@Override
	public RouteSearchResult saveRouteSearch(RouteSearchResult routeSearchResult) {
		routeSearches.put(routeSearchResult.routeSearchId(), routeSearchResult);
		return routeSearchResult;
	}
}
