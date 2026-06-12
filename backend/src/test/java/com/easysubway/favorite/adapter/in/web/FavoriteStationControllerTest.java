package com.easysubway.favorite.adapter.in.web;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
class FavoriteStationControllerTest {

	@Autowired
	private MockMvc mockMvc;

	@Test
	void favoriteStationsCanBeSavedListedAndRemoved() throws Exception {
		mockMvc.perform(put("/api/v1/me/favorite-stations/station-sangnoksu")
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
					{
					  "userId": "anonymous-user-1"
					}
					"""))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.success").value(true))
			.andExpect(jsonPath("$.data.userId").value("anonymous-user-1"))
			.andExpect(jsonPath("$.data.stationId").value("station-sangnoksu"))
			.andExpect(jsonPath("$.data.nameKo").value("상록수"))
			.andExpect(jsonPath("$.data.region").value("수도권"))
			.andExpect(jsonPath("$.data.dataQualityLevel").value("LEVEL_1"))
			.andExpect(jsonPath("$.data.lines[0].name").value("수도권 4호선"))
			.andExpect(jsonPath("$.data.addedAt").isNotEmpty());

		mockMvc.perform(get("/api/v1/me/favorite-stations")
				.param("userId", "anonymous-user-1"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.success").value(true))
			.andExpect(jsonPath("$.data[0].stationId").value("station-sangnoksu"))
			.andExpect(jsonPath("$.data[0].nameKo").value("상록수"));

		mockMvc.perform(delete("/api/v1/me/favorite-stations/station-sangnoksu")
				.param("userId", "anonymous-user-1"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.success").value(true));

		mockMvc.perform(get("/api/v1/me/favorite-stations")
				.param("userId", "anonymous-user-1"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.data").isEmpty());
	}

	@Test
	void favoriteStationsRejectUnknownStation() throws Exception {
		mockMvc.perform(put("/api/v1/me/favorite-stations/missing-station")
				.contentType(MediaType.APPLICATION_JSON)
				.content("""
					{
					  "userId": "anonymous-user-2"
					}
					"""))
			.andExpect(status().isNotFound())
			.andExpect(jsonPath("$.success").value(false))
			.andExpect(jsonPath("$.data").doesNotExist())
			.andExpect(jsonPath("$.message").value("역 정보를 찾을 수 없습니다."));
	}

	@Test
	void favoriteStationsRequireUserId() throws Exception {
		mockMvc.perform(get("/api/v1/me/favorite-stations"))
			.andExpect(status().isBadRequest())
			.andExpect(jsonPath("$.success").value(false))
			.andExpect(jsonPath("$.data").doesNotExist())
			.andExpect(jsonPath("$.message").value("사용자 식별자가 필요합니다."));
	}
}
