package com.easysubway.route.application.port.out;

import com.easysubway.route.domain.RouteSearchDashboardSummary;
import com.easysubway.route.domain.RouteSearchResult;
import java.util.List;

public interface SummarizeRouteSearchPort {

	RouteSearchDashboardSummary summarizeRouteSearches();

	List<RouteSearchResult> loadRouteSearchesForDashboard();
}
