package com.easysubway.auth.adapter.in.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@DisplayName("익명 사용자 인증 API")
class AnonymousAuthControllerTest {

	@Autowired
	private MockMvc mockMvc;

	@Test
	@DisplayName("익명 사용자를 발급하고 같은 Basic 인증 정보로 현재 사용자를 조회한다")
	void issueAnonymousUserAndReadCurrentUser() throws Exception {
		var result = mockMvc.perform(post("/api/v1/auth/anonymous"))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.success").value(true))
			.andExpect(jsonPath("$.data.userId").isNotEmpty())
			.andExpect(jsonPath("$.data.password").isNotEmpty())
			.andExpect(jsonPath("$.data.authType").value("BASIC"))
			.andExpect(jsonPath("$.data.anonymous").value(true))
			.andExpect(jsonPath("$.data.createdAt").isNotEmpty())
			.andReturn();

		String body = result.getResponse().getContentAsString();
		String userId = JsonPath.read(body, "$.data.userId");
		String password = JsonPath.read(body, "$.data.password");

		assertThat(userId).startsWith("anonymous-");

		mockMvc.perform(get("/api/v1/me")
				.with(httpBasic(userId, password)))
			.andExpect(status().isOk())
			.andExpect(jsonPath("$.success").value(true))
			.andExpect(jsonPath("$.data.userId").value(userId))
			.andExpect(jsonPath("$.data.authType").value("BASIC"))
			.andExpect(jsonPath("$.data.anonymous").value(true));
	}

	@Test
	@DisplayName("현재 사용자 조회는 인증을 요구한다")
	void currentUserRequiresAuthentication() throws Exception {
		mockMvc.perform(get("/api/v1/me"))
			.andExpect(status().isUnauthorized());
	}
}
