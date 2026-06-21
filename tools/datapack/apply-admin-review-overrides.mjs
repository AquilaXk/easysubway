#!/usr/bin/env node
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "../..");
const allowedFacilityStatuses = new Set(["NORMAL", "BROKEN", "UNDER_CONSTRUCTION", "CLOSED", "UNKNOWN"]);
const availableFacilityStatuses = new Set(["NORMAL"]);

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const fixturePath = path.resolve(root, requireArg(args, "fixture"));
  const overridesPath = path.resolve(root, requireArg(args, "overrides"));
  const outputPath = path.resolve(root, requireArg(args, "output"));

  const fixture = JSON.parse(await readFile(fixturePath, "utf8"));
  const overrides = JSON.parse(await readFile(overridesPath, "utf8"));
  applyAdminReviewOverrides(fixture, overrides);
  await writeFile(outputPath, `${JSON.stringify(fixture, null, 2)}\n`);
}

function applyAdminReviewOverrides(fixture, overrides) {
  if (overrides.schemaVersion !== 1) {
    throw new Error("admin review overrides schemaVersion must be 1");
  }
  const source = requiredString(overrides.source, "source");
  const updates = requiredArray(overrides.facilityStatusUpdates, "facilityStatusUpdates");
  const packs = requiredArray(fixture.packs, "fixture.packs");
  const latestUpdates = latestFacilityUpdates(updates);
  let appliedCount = 0;

  for (const { facilityId, status } of latestUpdates.values()) {
    const matchedFacilities = [];
    for (const pack of packs) {
      const facilities = requiredArray(pack.facilities, "pack.facilities");
      for (const facility of facilities) {
        if (facility.id === facilityId) {
          facility.status = status;
          applyRouteAccessibilityOverride(pack, facility, status);
          applyStationAccessibilitySummaryOverride(pack, facility, status);
          matchedFacilities.push(facility);
        }
      }
    }
    if (matchedFacilities.length === 0) {
      throw new Error(`facilityStatusUpdates.facilityId was not found in fixture: ${facilityId}`);
    }
    appliedCount += matchedFacilities.length;
  }

  for (const pack of packs) {
    pack.metadata = {
      ...(pack.metadata ?? {}),
      adminReviewOverrideSource: source,
      adminReviewOverrideCount: String(appliedCount),
      adminReviewOverrideExportedAt: requiredString(overrides.exportedAt, "exportedAt"),
    };
  }
}

function latestFacilityUpdates(updates) {
  const latest = new Map();
  updates.forEach((update, sequence) => {
    const facilityId = requiredString(update.facilityId, "facilityStatusUpdates.facilityId");
    const status = requiredString(update.status, "facilityStatusUpdates.status").toUpperCase();
    requiredString(update.reportId, "facilityStatusUpdates.reportId");
    requiredString(update.reviewedBy, "facilityStatusUpdates.reviewedBy");
    const reviewedAt = reviewedAtMillis(update.reviewedAt);
    if (!allowedFacilityStatuses.has(status)) {
      throw new Error(`facilityStatusUpdates.status is not supported: ${status}`);
    }

    const current = latest.get(facilityId);
    if (
      current == null ||
      reviewedAt > current.reviewedAt ||
      (reviewedAt === current.reviewedAt && sequence > current.sequence)
    ) {
      latest.set(facilityId, { facilityId, status, reviewedAt, sequence });
    }
  });
  return latest;
}

function applyStationAccessibilitySummaryOverride(pack, facility, status) {
  const stationId = requiredString(facility.stationId, "facility.stationId");
  const facilityName = requiredString(facility.name, "facility.name");
  const summaries = pack.stationAccessibilitySummaries ?? [];
  pack.stationAccessibilitySummaries = summaries;
  let summary = summaries.find((row) => row.stationId === stationId);
  if (summary == null) {
    summary = { stationId, summary: "", warning: "" };
    summaries.push(summary);
  }
  const message = stationAccessibilityMessage(facilityName, status);
  summary.summary = message.summary;
  summary.warning = message.warning;
}

function stationAccessibilityMessage(facilityName, status) {
  switch (status) {
    case "NORMAL":
      return { summary: `${facilityName} 이용 가능`, warning: "" };
    case "UNKNOWN":
      return {
        summary: `${facilityName} 상태 확인 필요`,
        warning: `${facilityName} 상태가 관리자 검수에서 확인 필요로 표시되었습니다.`,
      };
    case "BROKEN":
      return {
        summary: `${facilityName} 이용 제한`,
        warning: `${facilityName} 고장으로 우회가 필요합니다.`,
      };
    case "UNDER_CONSTRUCTION":
      return {
        summary: `${facilityName} 이용 제한`,
        warning: `${facilityName} 공사 중으로 우회가 필요합니다.`,
      };
    case "CLOSED":
      return {
        summary: `${facilityName} 이용 제한`,
        warning: `${facilityName} 폐쇄로 우회가 필요합니다.`,
      };
    default:
      throw new Error(`facilityStatusUpdates.status is not supported: ${status}`);
  }
}

function applyRouteAccessibilityOverride(pack, facility, status) {
  const accessibilityStatus = routeAccessibilityStatus(status);
  if (accessibilityStatus == null) {
    return;
  }

  for (const edge of pack.networkEdges ?? []) {
    if (edge.facilityId === facility.id) {
      edge.accessibilityStatus = accessibilityStatus;
    }
  }

  const facilityType = requiredString(facility.type, "facility.type").toUpperCase();
  if (facilityType !== "ELEVATOR" && facilityType !== "ESCALATOR") {
    return;
  }
  const stationId = requiredString(facility.stationId, "facility.stationId");
  const stationNodeIds = new Set(
    (pack.internalRouteNodes ?? [])
      .filter((node) => node.stationId === stationId)
      .map((node) => requiredString(node.id, "internalRouteNodes.id")),
  );
  for (const edge of pack.internalRouteEdges ?? []) {
    if (!stationNodeIds.has(edge.fromNodeId) && !stationNodeIds.has(edge.toNodeId)) {
      continue;
    }
    if (facilityType === "ELEVATOR" && (edge.requiresElevator === true || edge.edgeType === "ELEVATOR")) {
      edge.accessibilityStatus = accessibilityStatus;
    }
    if (facilityType === "ESCALATOR" && (edge.requiresEscalator === true || edge.edgeType === "ESCALATOR")) {
      edge.accessibilityStatus = accessibilityStatus;
    }
  }
}

function routeAccessibilityStatus(status) {
  if (availableFacilityStatuses.has(status)) {
    return "AVAILABLE";
  }
  if (status === "UNKNOWN") {
    return "UNKNOWN";
  }
  return "UNAVAILABLE";
}

function reviewedAtMillis(value) {
  const reviewedAt = requiredString(value, "facilityStatusUpdates.reviewedAt");
  const millis = Date.parse(reviewedAt);
  if (Number.isNaN(millis)) {
    throw new Error(`facilityStatusUpdates.reviewedAt is invalid: ${reviewedAt}`);
  }
  return millis;
}

function parseArgs(argv) {
  const args = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const key = argv[index];
    const value = argv[index + 1];
    if (!key?.startsWith("--") || value == null || value.startsWith("--")) {
      throw new Error(`invalid argument near ${key ?? ""}`);
    }
    const name = key.slice(2);
    if (args.has(name)) {
      throw new Error(`duplicate argument: --${name}`);
    }
    args.set(name, value);
  }
  return args;
}

function requireArg(args, name) {
  const value = args.get(name);
  if (!value) {
    throw new Error(`--${name} is required`);
  }
  return value;
}

function requiredString(value, label) {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${label} is required`);
  }
  return value.trim();
}

function requiredArray(value, label) {
  if (!Array.isArray(value)) {
    throw new Error(`${label} must be an array`);
  }
  return value;
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
