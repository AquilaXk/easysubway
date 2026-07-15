package com.easysubway.route.adapter.out.integrity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.content;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.header;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

@DisplayName("Google Play Integrity decode adapter")
class GooglePlayIntegrityDecoderTest {

	@Test
	@DisplayName("공식 decode endpoint 응답에서 검증 대상 verdict만 추출한다")
	void decodesOfficialTokenPayload() {
		RestClient.Builder builder = RestClient.builder();
		MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
		server.expect(requestTo(
			"https://playintegrity.googleapis.com/v1/com.easysubway.app:decodeIntegrityToken"
		))
			.andExpect(header("Authorization", "Bearer google-access-token"))
			.andExpect(content().json("{\"integrityToken\":\"integrity-token\"}"))
			.andRespond(withSuccess("""
				{
				  "tokenPayloadExternal": {
				    "requestDetails": {
				      "requestPackageName": "com.easysubway.app",
				      "requestHash": "request-hash",
				      "timestampMillis": "1784192400000"
				    },
				    "appIntegrity": {
				      "packageName": "com.easysubway.app",
				      "appRecognitionVerdict": "PLAY_RECOGNIZED",
				      "certificateSha256Digest": ["certificate-digest"]
				    },
				    "accountDetails": {"appLicensingVerdict": "LICENSED"},
				    "deviceIntegrity": {
				      "deviceRecognitionVerdict": ["MEETS_DEVICE_INTEGRITY"]
				    }
				  }
				}
				""", MediaType.APPLICATION_JSON));
		var decoder = new GooglePlayIntegrityDecoder(builder, new ObjectMapper(), () -> "google-access-token");

		var verdict = decoder.decode("integrity-token");

		assertThat(verdict.requestPackageName()).isEqualTo("com.easysubway.app");
		assertThat(verdict.requestHash()).isEqualTo("request-hash");
		assertThat(verdict.requestTimestamp()).isEqualTo("2026-07-16T09:00:00Z");
		assertThat(verdict.appPackageName()).isEqualTo("com.easysubway.app");
		assertThat(verdict.appRecognitionVerdict()).isEqualTo("PLAY_RECOGNIZED");
		assertThat(verdict.certificateSha256Digests()).containsExactly("certificate-digest");
		assertThat(verdict.appLicensingVerdict()).isEqualTo("LICENSED");
		assertThat(verdict.deviceRecognitionVerdicts()).containsExactly("MEETS_DEVICE_INTEGRITY");
		server.verify();
	}
}
