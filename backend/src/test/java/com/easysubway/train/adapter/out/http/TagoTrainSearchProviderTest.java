package com.easysubway.train.adapter.out.http;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.tuple;

import com.easysubway.train.application.TrainSearchProvider.ProviderFailure;
import com.easysubway.train.domain.TrainSearchModels.Journey;
import com.easysubway.train.domain.TrainSearchModels.LegQuery;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.net.http.HttpClient;
import java.time.Clock;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;

class TagoTrainSearchProviderTest {

	private static final ObjectMapper JSON = new ObjectMapper();

	@Test
	void removesItxCheongchunButKeepsDaejeonKtx() throws Exception {
		var provider = new TagoTrainSearchProvider(
			"never-print-service-key",
			JSON,
			HttpClient.newHttpClient(),
			Clock.fixed(Instant.parse("2026-07-19T00:00:00Z"), ZoneOffset.UTC),
			URI.create("http://127.0.0.1/")
		);
		var query = new LegQuery(
			"NAT010000",
			"NAT011668",
			LocalDate.parse("2026-07-20"),
			null
		);

		var journeys = provider.parseJourneys(JSON.readTree("""
			{"response":{"header":{"resultCode":"00","resultMsg":"NORMAL SERVICE."},"body":{
			  "items":{"item":[
			    {"trainno":"101","traingradename":"KTX","depplandtime":"20260720090000","arrplandtime":"20260720100200","depplacename":"서울","arrplacename":"대전","adultcharge":"23700"},
			    {"trainno":"2001","traingradename":"ITX-청춘","depplandtime":"20260720091000","arrplandtime":"20260720110000","depplacename":"서울","arrplacename":"대전","adultcharge":"10000"}
			  ]},"pageNo":1,"numOfRows":100,"totalCount":2
			}}}
			"""), query);

		assertThat(journeys)
			.extracting(Journey::trainType, Journey::trainNumber, Journey::adultFareWon, Journey::durationMinutes)
			.containsExactly(tuple("KTX", "101", 23_700, 62));
		assertThat(journeys.getFirst().departureStationId()).isEqualTo("NAT010000");
		assertThat(journeys.getFirst().arrivalStationId()).isEqualTo("NAT011668");
	}

	@Test
	void loadsNonPaginatedCatalogOperationsAndPaginatedStations() throws Exception {
		var requests = new ConcurrentHashMap<String, Map<String, String>>();
		var server = server((exchange) -> {
			String operation = exchange.getRequestURI().getPath().substring(1);
			requests.put(operation, query(exchange.getRequestURI()));
			switch (operation) {
				case "GetCtyCodeList" -> respond(exchange, catalogResponse("""
					[{"citycode":"11","cityname":"서울"}]
					"""));
				case "GetVhcleKndList" -> respond(exchange, catalogResponse("""
					[
					  {"vehiclekndid":"00","vehiclekndnm":"KTX"},
					  {"vehiclekndid":"01","vehiclekndnm":"KTX-산천"},
					  {"vehiclekndid":"10","vehiclekndnm":"KTX-산천"},
					  {"vehiclekndid":"02","vehiclekndnm":"SRT"},
					  {"vehiclekndid":"03","vehiclekndnm":"ITX-마음"},
					  {"vehiclekndid":"04","vehiclekndnm":"ITX-새마을"},
					  {"vehiclekndid":"05","vehiclekndnm":"새마을호"},
					  {"vehiclekndid":"06","vehiclekndnm":"무궁화호"},
					  {"vehiclekndid":"08","vehiclekndnm":"누리로"},
					  {"vehiclekndid":"07","vehiclekndnm":"ITX-청춘"}
					]
					"""));
				case "GetCtyAcctoTrainSttnList" -> respond(exchange, paginatedResponse("""
					[
					  {"nodeid":"NAT010000","nodename":"서울"},
					  {"nodeid":"NAT011668","nodename":"대전"}
					]
					""", 2));
				default -> respond(exchange, 404, "{}");
			}
		});
		try {
			var provider = provider(server, "encoded%2Bservice%2Fkey");

			var catalog = provider.catalog();

			assertThat(catalog.observedAt()).isEqualTo(Instant.parse("2026-07-19T00:00:00Z"));
			assertThat(catalog.stations()).extracting(station -> station.name())
				.containsExactly("대전", "서울");
			assertThat(catalog.trainTypes()).extracting(type -> type.code())
				.containsExactly(
					"ITX_MAUM", "ITX_SAEMAEUL", "KTX", "KTX_SANCHEON",
					"MUGUNGHWA", "NURIRO", "SAEMAEUL", "SRT"
				);
			assertThat(catalog.trainTypes())
				.filteredOn(type -> "KTX_SANCHEON".equals(type.code()))
				.singleElement()
				.extracting(type -> type.providerCodes())
				.isEqualTo(java.util.List.of("01", "10"));
			assertThat(requests.get("GetCtyCodeList")).doesNotContainKeys("pageNo", "numOfRows");
			assertThat(requests.get("GetVhcleKndList")).doesNotContainKeys("pageNo", "numOfRows");
			assertThat(requests.get("GetCtyAcctoTrainSttnList"))
				.containsEntry("cityCode", "11")
				.containsEntry("pageNo", "1")
				.containsEntry("numOfRows", "100")
				.containsEntry("serviceKey", "encoded+service/key");
		} finally {
			server.stop(0);
		}
	}

	@Test
	void searchesWithNormalizedQueryAndDoesNotExposeSecretOnProviderFailure() throws Exception {
		var requests = new ConcurrentHashMap<String, Map<String, String>>();
		var server = server((exchange) -> {
			String operation = exchange.getRequestURI().getPath().substring(1);
			requests.put(operation, query(exchange.getRequestURI()));
			if ("GetStrtpntAlocFndTrainInfo".equals(operation)) {
				respond(exchange, paginatedResponse("""
					[{"trainno":"101","traingradename":"KTX","depplandtime":"20260720090000","arrplandtime":"20260720100200","depplacename":"서울","arrplacename":"대전","adultcharge":"23700"}]
					""", 1));
				return;
			}
			respond(exchange, 500, "secret must not escape");
		});
		try {
			var provider = provider(server, "never-print-service-key");
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-07-20"), "KTX", "00");

			assertThat(provider.search(query)).hasSize(1);
			assertThat(requests.get("GetStrtpntAlocFndTrainInfo"))
				.containsEntry("depPlaceId", "NAT010000")
				.containsEntry("arrPlaceId", "NAT011668")
				.containsEntry("depPlandTime", "20260720")
				.containsEntry("trainGradeCode", "00")
				.containsEntry("pageNo", "1")
				.containsEntry("numOfRows", "100");

			var failing = provider(server, "literal-secret-value");
			assertThatThrownBy(failing::catalog)
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_PROVIDER_ERROR")
				.hasMessageNotContaining("literal-secret-value")
				.hasMessageNotContaining("secret must not escape");
		} finally {
			server.stop(0);
		}
	}

	@Test
	void searchesEveryProviderCodeForOneCanonicalTrainType() throws Exception {
		var requestedCodes = ConcurrentHashMap.<String>newKeySet();
		var server = server(exchange -> {
			String providerCode = query(exchange.getRequestURI()).get("trainGradeCode");
			requestedCodes.add(providerCode);
			String trainNumber = "01".equals(providerCode) ? "101" : "102";
			respond(exchange, paginatedResponse("""
				{"trainno":"%s","traingradename":"KTX-산천","depplandtime":"20260720090000","arrplandtime":"20260720100200","depplacename":"서울","arrplacename":"대전","adultcharge":"23700"}
				""".formatted(trainNumber), 1));
		});
		try {
			var query = new LegQuery(
				"NAT010000",
				"NAT011668",
				LocalDate.parse("2026-07-20"),
				"KTX_SANCHEON",
				java.util.List.of("01", "10")
			);

			assertThat(provider(server, "test-key").search(query))
				.extracting(Journey::trainNumber)
				.containsExactly("101", "102");
			assertThat(requestedCodes).containsExactlyInAnyOrder("01", "10");
		} finally {
			server.stop(0);
		}
	}

	@Test
	void mergesPagesAndAcceptsSingleItemShape() throws Exception {
		var requestedPages = new java.util.concurrent.CopyOnWriteArrayList<String>();
		var budgetCalls = new AtomicInteger();
		var server = server(exchange -> {
			Map<String, String> parameters = query(exchange.getRequestURI());
			requestedPages.add(parameters.get("pageNo"));
			int page = Integer.parseInt(parameters.get("pageNo"));
			String items = page == 1 ? journeyRows(1, 100) : journeyRow(101);
			respond(exchange, paginatedResponse(items, 101, page));
		});
		try {
			var provider = provider(server, "test-key", budgetCalls::incrementAndGet);
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-07-20"), "KTX", "00");

			assertThat(provider.search(query)).hasSize(101);
			assertThat(requestedPages).containsExactly("1", "2");
			assertThat(budgetCalls).hasValue(2);
		} finally {
			server.stop(0);
		}
	}

	@Test
	void retriesOneTransportFailureBeforeResponse() throws Exception {
		var attempts = new AtomicInteger();
		var server = server(exchange -> {
			if (attempts.incrementAndGet() == 1) {
				exchange.close();
				return;
			}
			respond(exchange, paginatedResponse("""
				{"trainno":"101","traingradename":"KTX","depplandtime":"20260720090000","arrplandtime":"20260720100200","depplacename":"서울","arrplacename":"대전","adultcharge":"23700"}
				""", 1));
		});
		try {
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-07-20"), "KTX", "00");

			assertThat(provider(server, "test-key").search(query)).hasSize(1);
			assertThat(attempts).hasValue(2);
		} finally {
			server.stop(0);
		}
	}

	@Test
	void rejectsHttpFailureEvenWhenBodyLooksSuccessful() throws Exception {
		var server = server(exchange -> respond(exchange, 500, paginatedResponse("[]", 0)));
		try {
			var provider = provider(server, "literal-secret-value");
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-07-20"), "KTX", "00");

			assertThatThrownBy(() -> provider.search(query))
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_PROVIDER_ERROR")
				.hasMessageNotContaining("literal-secret-value");
		} finally {
			server.stop(0);
		}
	}

	@Test
	void rejectsAPageThatMakesNoProgress() throws Exception {
		var server = server(exchange -> respond(exchange, paginatedResponse("[]", 1)));
		try {
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-07-20"), "KTX", "00");

			assertThatThrownBy(() -> provider(server, "test-key").search(query))
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_PROVIDER_ERROR");
		} finally {
			server.stop(0);
		}
	}

	@Test
	void rejectsPageMetadataMismatchAndTotalDrift() throws Exception {
		var wrongPage = server(exchange -> respond(exchange, paginatedResponse(journeyRow(1), 1, 2)));
		try {
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-07-20"), "KTX", "00");
			assertThatThrownBy(() -> provider(wrongPage, "test-key").search(query))
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_PROVIDER_ERROR");
		} finally {
			wrongPage.stop(0);
		}

		var drift = server(exchange -> {
			int page = Integer.parseInt(query(exchange.getRequestURI()).get("pageNo"));
			respond(exchange, paginatedResponse(page == 1 ? journeyRows(1, 100) : journeyRow(101), page == 1 ? 101 : 102, page));
		});
		try {
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-07-20"), "KTX", "00");
			assertThatThrownBy(() -> provider(drift, "test-key").search(query))
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_PROVIDER_ERROR");
		} finally {
			drift.stop(0);
		}
	}

	@Test
	void malformedJourneyIsTypedAsNoValidRows() throws Exception {
		var server = server(exchange -> respond(exchange, paginatedResponse("""
			{"trainno":"101","traingradename":"KTX","depplandtime":"not-a-time","arrplandtime":"20260720100200","depplacename":"서울","arrplacename":"대전","adultcharge":"23700"}
			""", 1)));
		try {
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-07-20"), "KTX", "00");
			assertThatThrownBy(() -> provider(server, "test-key").search(query))
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_NO_VALID_ROWS");
		} finally {
			server.stop(0);
		}
	}

	@Test
	void rejectsInvalidCalendarDateInsteadOfNormalizingIt() throws Exception {
		var server = server(exchange -> respond(exchange, paginatedResponse("""
			{"trainno":"101","traingradename":"KTX","depplandtime":"20260230090000","arrplandtime":"20260230100200","depplacename":"서울","arrplacename":"대전","adultcharge":"23700"}
			""", 1)));
		try {
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-02-28"), "KTX", "00");
			assertThatThrownBy(() -> provider(server, "test-key").search(query))
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_NO_VALID_ROWS");
		} finally {
			server.stop(0);
		}
	}

	@Test
	void rejectsJourneyOutsideRequestedDate() throws Exception {
		var server = server(exchange -> respond(exchange, paginatedResponse("""
			{"trainno":"101","traingradename":"KTX","depplandtime":"20260721090000","arrplandtime":"20260721100200","depplacename":"서울","arrplacename":"대전","adultcharge":"23700"}
			""", 1)));
		try {
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-07-20"), "KTX", "00");
			assertThatThrownBy(() -> provider(server, "test-key").search(query))
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_NO_VALID_ROWS");
		} finally {
			server.stop(0);
		}
	}

	@Test
	void rejectsJourneyWhoseTrainTypeDiffersFromRequestedGrade() throws Exception {
		var server = server(exchange -> respond(exchange, paginatedResponse("""
			{"trainno":"301","traingradename":"SRT","depplandtime":"20260720090000","arrplandtime":"20260720100200","depplacename":"서울","arrplacename":"대전","adultcharge":"23700"}
			""", 1)));
		try {
			var query = new LegQuery("NAT010000", "NAT011668", LocalDate.parse("2026-07-20"), "KTX", "00");
			assertThatThrownBy(() -> provider(server, "test-key").search(query))
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_NO_VALID_ROWS");
		} finally {
			server.stop(0);
		}
	}

	@Test
	void missingKeyAndEmptyCatalogFailClosed() throws Exception {
		var requests = new AtomicInteger();
		var server = server(exchange -> {
			requests.incrementAndGet();
			respond(exchange, catalogResponse("[]"));
		});
		try {
			assertThatThrownBy(() -> provider(server, "").catalog())
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_PROVIDER_ERROR");
			assertThat(requests).hasValue(0);

			assertThatThrownBy(() -> provider(server, "test-key").catalog())
				.isInstanceOf(ProviderFailure.class)
				.hasMessage("TRAIN_SEARCH_PROVIDER_ERROR");
			assertThat(requests).hasValue(2);
		} finally {
			server.stop(0);
		}
	}

	private TagoTrainSearchProvider provider(HttpServer server, String serviceKey) {
		return provider(server, serviceKey, () -> {});
	}

	private TagoTrainSearchProvider provider(
		HttpServer server,
		String serviceKey,
		com.easysubway.train.application.TrainSearchProviderCallBudget budget
	) {
		return new TagoTrainSearchProvider(
			serviceKey,
			JSON,
			HttpClient.newHttpClient(),
			Clock.fixed(Instant.parse("2026-07-19T00:00:00Z"), ZoneOffset.UTC),
			URI.create("http://127.0.0.1:" + server.getAddress().getPort() + "/"),
			budget
		);
	}

	private HttpServer server(ExchangeHandler handler) throws IOException {
		var server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
		server.createContext("/", exchange -> handler.handle(exchange));
		server.start();
		return server;
	}

	private String catalogResponse(String items) {
		return "{\"response\":{\"header\":{\"resultCode\":\"00\"},\"body\":{\"items\":{\"item\":"
			+ items + "}}}}";
	}

	private String paginatedResponse(String items, int totalCount) {
		return paginatedResponse(items, totalCount, 1);
	}

	private String paginatedResponse(String items, int totalCount, int pageNo) {
		return "{\"response\":{\"header\":{\"resultCode\":\"00\"},\"body\":{\"items\":{\"item\":"
			+ items + "},\"pageNo\":" + pageNo + ",\"numOfRows\":100,\"totalCount\":" + totalCount + "}}}";
	}

	private String journeyRows(int start, int count) {
		return IntStream.range(start, start + count)
			.mapToObj(this::journeyRow)
			.collect(java.util.stream.Collectors.joining(",", "[", "]"));
	}

	private String journeyRow(int trainNumber) {
		return "{\"trainno\":\"" + trainNumber
			+ "\",\"traingradename\":\"KTX\",\"depplandtime\":\"20260720090000\","
			+ "\"arrplandtime\":\"20260720100200\",\"depplacename\":\"서울\","
			+ "\"arrplacename\":\"대전\",\"adultcharge\":\"23700\"}";
	}

	private Map<String, String> query(URI uri) {
		var values = new ConcurrentHashMap<String, String>();
		if (uri.getRawQuery() == null) return values;
		Arrays.stream(uri.getRawQuery().split("&")).forEach(part -> {
			String[] pair = part.split("=", 2);
			values.put(
				URLDecoder.decode(pair[0], StandardCharsets.UTF_8),
				URLDecoder.decode(pair.length == 1 ? "" : pair[1], StandardCharsets.UTF_8)
			);
		});
		return values;
	}

	private void respond(HttpExchange exchange, String body) throws IOException {
		respond(exchange, 200, body);
	}

	private void respond(HttpExchange exchange, int status, String body) throws IOException {
		byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
		exchange.getResponseHeaders().set("Content-Type", "application/json");
		exchange.sendResponseHeaders(status, bytes.length);
		exchange.getResponseBody().write(bytes);
		exchange.close();
	}

	@FunctionalInterface
	private interface ExchangeHandler {
		void handle(HttpExchange exchange) throws IOException;
	}
}
