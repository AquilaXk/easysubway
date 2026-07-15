package com.easysubway.datapack.application.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDateTime;
import java.time.Period;
import java.util.HashMap;
import java.util.HexFormat;
import java.util.Map;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.ClassPathResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Component;

@Component
public class DatapackSourceGovernancePolicy {

	private static final String POLICY_RESOURCE = "datapack/source-governance-policy.json";
	private static final String FRESHNESS_RESOURCE = "datapack/datapack-freshness-sla.json";

	private final String version;
	private final String sha256;
	private final Map<String, Integer> retentionDaysBySource;
	private final Map<String, Period> freshnessCadenceBySource;

	@Autowired
	public DatapackSourceGovernancePolicy(ObjectMapper objectMapper) {
		this(
			objectMapper,
			new ClassPathResource(POLICY_RESOURCE),
			new ClassPathResource(FRESHNESS_RESOURCE)
		);
	}

	DatapackSourceGovernancePolicy(ObjectMapper objectMapper, Resource governanceResource, Resource freshnessResource) {
		try (InputStream governanceInput = governanceResource.getInputStream();
			InputStream freshnessInput = freshnessResource.getInputStream()) {
			byte[] bytes = governanceInput.readAllBytes();
			JsonNode policy = objectMapper.readTree(bytes);
			JsonNode freshnessPolicy = objectMapper.readTree(freshnessInput);
			this.version = requiredText(policy.path("policyVersion"), "policyVersion");
			this.sha256 = sha256(bytes);
			this.retentionDaysBySource = retentionDays(policy);
			this.freshnessCadenceBySource = freshnessCadences(freshnessPolicy);
		} catch (IOException exception) {
			throw new IllegalStateException("Datapack source governance policy could not be loaded.", exception);
		}
	}

	String version() {
		return version;
	}

	String sha256() {
		return sha256;
	}

	Binding requireBinding(
		String sourceId,
		LocalDateTime retrievedAt,
		LocalDateTime submittedFreshnessExpiry,
		LocalDateTime submittedExpiry,
		String submittedVersion,
		String submittedSha256
	) {
		Integer retentionDays = retentionDaysBySource.get(sourceId);
		Period freshnessCadence = freshnessCadenceBySource.get(sourceId);
		if (retentionDays == null || !version.equals(submittedVersion) || !sha256.equals(submittedSha256)) {
			throw new IllegalArgumentException("SOURCE_GOVERNANCE_OWNER_MISSING: current policy binding");
		}
		if (freshnessCadence == null) {
			throw new IllegalArgumentException("SOURCE_FRESHNESS_POLICY_MISSING: backend freshness basis");
		}
		LocalDateTime freshnessExpiry = retrievedAt.plus(freshnessCadence);
		if (!freshnessExpiry.equals(submittedFreshnessExpiry)) {
			throw new IllegalArgumentException(
				"SOURCE_FRESHNESS_DERIVATION_MISMATCH: freshness expiry must match current policy"
			);
		}
		LocalDateTime expiry = retrievedAt.plusDays(retentionDays);
		if (!expiry.equals(submittedExpiry)) {
			throw new IllegalArgumentException("RAW_RETENTION_OVERDUE: retention expiry must match current policy");
		}
		return new Binding(version, sha256, freshnessExpiry, expiry);
	}

	private static Map<String, Period> freshnessCadences(JsonNode policy) {
		Map<String, Period> result = new HashMap<>();
		for (JsonNode sourceClass : policy.path("sourceClasses")) {
			if (!"retrievedAt".equals(sourceClass.path("basisField").asText())
				|| sourceClass.has("providerValidityEndField")) {
				continue;
			}
			String cadenceText = sourceClass.hasNonNull("reverificationCadence")
				? sourceClass.path("reverificationCadence").asText()
				: sourceClass.path("maximumReverificationCadence").asText();
			Period cadence;
			try {
				cadence = Period.parse(cadenceText);
			} catch (RuntimeException exception) {
				throw new IllegalStateException("Datapack source freshness cadence is invalid.", exception);
			}
			if (cadence.isZero() || cadence.isNegative()) {
				throw new IllegalStateException("Datapack source freshness cadence is invalid.");
			}
			for (JsonNode sourceIdNode : sourceClass.path("sourceIds")) {
				String sourceId = requiredText(sourceIdNode, "sourceClasses[].sourceIds[]");
				if (result.put(sourceId, cadence) != null) {
					throw new IllegalStateException("Datapack source freshness binding is duplicated.");
				}
			}
		}
		return Map.copyOf(result);
	}

	private static Map<String, Integer> retentionDays(JsonNode policy) {
		Map<String, Integer> daysByClass = new HashMap<>();
		for (JsonNode retentionClass : policy.path("retentionClasses")) {
			String id = requiredText(retentionClass.path("id"), "retentionClasses[].id");
			int days = retentionClass.path("retentionDays").asInt(0);
			if (days < 1 || daysByClass.put(id, days) != null) {
				throw new IllegalStateException("Datapack source governance retention class is invalid.");
			}
		}
		Map<String, Integer> result = new HashMap<>();
		for (JsonNode source : policy.path("sources")) {
			String sourceId = requiredText(source.path("sourceId"), "sources[].sourceId");
			String classId = requiredText(source.path("retentionClassId"), "sources[].retentionClassId");
			Integer days = daysByClass.get(classId);
			if (days == null || result.put(sourceId, days) != null) {
				throw new IllegalStateException("Datapack source governance source binding is invalid.");
			}
		}
		return Map.copyOf(result);
	}

	private static String requiredText(JsonNode value, String field) {
		if (!value.isTextual() || value.textValue().isBlank()) {
			throw new IllegalStateException("Datapack source governance " + field + " is invalid.");
		}
		return value.textValue();
	}

	private static String sha256(byte[] bytes) {
		try {
			return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes));
		} catch (NoSuchAlgorithmException exception) {
			throw new IllegalStateException("SHA-256 is required.", exception);
		}
	}

	record Binding(
		String version,
		String sha256,
		LocalDateTime freshnessExpiresAt,
		LocalDateTime rawRetentionExpiresAt
	) {}
}
