import 'dart:convert';

import 'package:easysubway_mobile/features/routes/domain/route_identity.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trimmed wheelchair mobility keeps the strict query identity', () {
    final padded = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: ' WHEELCHAIR ',
    );
    final normalized = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'WHEELCHAIR',
    );

    expect(padded.trimmed().effectiveConstraintMode, 'STRICT_STEP_FREE');
    expect(padded.queryIdentity, normalized.queryIdentity);
  });

  test('query identity uses fixed UTF-8 JSON bytes and a stable hash', () {
    final identity = RouteQueryIdentity(
      originStationId: ' station-a ',
      destinationStationId: 'station-b ',
      mobilityType: 'WHEELCHAIR',
      constraintMode: 'STRICT_STEP_FREE',
      mobilityPreset: ' STEP_FREE ',
      transportScope: 'SUBWAY',
      objective: 'FASTEST',
    );

    expect(
      identity.canonicalBytes,
      utf8Bytes(
        '["route-query-v1","station-a","station-b",null,'
        '"WHEELCHAIR","STEP_FREE","STRICT_STEP_FREE","SUBWAY","FASTEST"]',
      ),
    );
    expect(
      identity.value,
      'rq:v1:44fc6a858ca383205a430f5726c55067f70fed47f42b654bb334a636690e48bc',
    );
    expect(RouteQueryIdentity.fromSnapshot(identity.toSnapshot()), identity);
    final untrustedSnapshot = {
      ...identity.toSnapshot(),
      'rawSearchText': '상록수 검색어',
      'latitude': '37.123',
      'providerToken': 'secret-token',
    };
    final restored = RouteQueryIdentity.fromSnapshot(untrustedSnapshot);
    expect(restored, identity);
    final restoredCanonicalText = utf8.decode(restored.canonicalBytes);
    expect(restoredCanonicalText, isNot(contains('상록수 검색어')));
    expect(restoredCanonicalText, isNot(contains('37.123')));
    expect(restoredCanonicalText, isNot(contains('secret-token')));
  });

  test(
    'query identity changes for each route query input but excludes raw search data',
    () {
      final base = RouteQueryIdentity(
        originStationId: 'a',
        destinationStationId: 'b',
        mobilityType: 'STANDARD',
        constraintMode: 'PREFER_STEP_FREE',
        transportScope: 'SUBWAY',
        objective: 'FASTEST',
      );
      final variants = [
        RouteQueryIdentity(
          originStationId: 'x',
          destinationStationId: 'b',
          mobilityType: 'STANDARD',
          constraintMode: 'PREFER_STEP_FREE',
          transportScope: 'SUBWAY',
          objective: 'FASTEST',
        ),
        RouteQueryIdentity(
          originStationId: 'a',
          destinationStationId: 'x',
          mobilityType: 'STANDARD',
          constraintMode: 'PREFER_STEP_FREE',
          transportScope: 'SUBWAY',
          objective: 'FASTEST',
        ),
        RouteQueryIdentity(
          originStationId: 'a',
          destinationStationId: 'b',
          mobilityType: 'SENIOR',
          constraintMode: 'PREFER_STEP_FREE',
          transportScope: 'SUBWAY',
          objective: 'FASTEST',
        ),
        RouteQueryIdentity(
          originStationId: 'a',
          destinationStationId: 'b',
          mobilityType: 'STANDARD',
          constraintMode: 'PREFER_STEP_FREE',
          waypointStationId: 'w',
          transportScope: 'SUBWAY',
          objective: 'FASTEST',
        ),
        RouteQueryIdentity(
          originStationId: 'a',
          destinationStationId: 'b',
          mobilityType: 'STANDARD',
          constraintMode: 'PREFER_STEP_FREE',
          mobilityPreset: 'STEP_FREE',
          transportScope: 'SUBWAY',
          objective: 'FASTEST',
        ),
        RouteQueryIdentity(
          originStationId: 'a',
          destinationStationId: 'b',
          mobilityType: 'STANDARD',
          constraintMode: 'STRICT_STEP_FREE',
          transportScope: 'SUBWAY',
          objective: 'FASTEST',
        ),
        RouteQueryIdentity(
          originStationId: 'a',
          destinationStationId: 'b',
          mobilityType: 'STANDARD',
          constraintMode: 'PREFER_STEP_FREE',
          transportScope: 'SUBWAY_AND_ITX_CHEONGCHUN',
          objective: 'FASTEST',
        ),
        RouteQueryIdentity(
          originStationId: 'a',
          destinationStationId: 'b',
          mobilityType: 'STANDARD',
          constraintMode: 'PREFER_STEP_FREE',
          transportScope: 'SUBWAY',
          objective: 'FEWEST_TRANSFERS',
        ),
      ];
      for (final variant in variants) {
        expect(variant, isNot(base));
        expect(variant.value, isNot(base.value));
      }
      final canonicalText = utf8.decode(base.canonicalBytes);
      expect(canonicalText, isNot(contains('상록수 검색어')));
      expect(canonicalText, isNot(contains('37.123')));
      expect(canonicalText, isNot(contains('secret-token')));
      final ambiguousLeft = RouteQueryIdentity(
        originStationId: 'ab',
        destinationStationId: 'c',
        mobilityType: 'STANDARD',
        constraintMode: 'PREFER_STEP_FREE',
        transportScope: 'SUBWAY',
        objective: 'FASTEST',
      );
      final ambiguousRight = RouteQueryIdentity(
        originStationId: 'a',
        destinationStationId: 'bc',
        mobilityType: 'STANDARD',
        constraintMode: 'PREFER_STEP_FREE',
        transportScope: 'SUBWAY',
        objective: 'FASTEST',
      );
      expect(ambiguousLeft.value, isNot(ambiguousRight.value));
      expect(
        base.value,
        isNot(
          RouteQueryIdentity(
            originStationId: 'local-a',
            destinationStationId: 'online-b',
            mobilityType: 'STANDARD',
            constraintMode: 'PREFER_STEP_FREE',
            transportScope: 'SUBWAY',
            objective: 'FASTEST',
          ).value,
        ),
      );
    },
  );

  test('candidate identity is ordered and ignores display-only provider data', () {
    final query = RouteQueryIdentity(
      originStationId: 'a',
      destinationStationId: 'b',
      mobilityType: 'STANDARD',
      constraintMode: 'PREFER_STEP_FREE',
      transportScope: 'SUBWAY',
      objective: 'FASTEST',
    );
    final first = RouteCandidateIdentity(
      query: query,
      legs: [
        RouteCandidateLegSignature(
          stepType: 'RIDE',
          fromStationId: 'a',
          toStationId: 'b',
          fromNodeId: 'n1',
          toNodeId: 'n2',
          edgeId: 'e1',
          lineId: 'l1',
          serviceClass: 'SUBWAY',
          servicePattern: 'LOCAL',
        ),
      ],
    );
    expect(
      first.canonicalBytes,
      utf8.encode(
        '["route-candidate-v1",["route-query-v1","a","b",null,"STANDARD",null,"PREFER_STEP_FREE","SUBWAY","FASTEST"],[["RIDE","a","b","n1","n2","e1","l1","SUBWAY","LOCAL"]]]',
      ),
    );
    expect(
      first.value,
      'rc:v1:aeb259ab45a445856f0277476cd61b04bf225036003f7a06e28faa4e4409e3aa',
    );
    final variants = [
      RouteCandidateIdentity(
        query: query,
        legs: [
          RouteCandidateLegSignature(
            stepType: 'WALK',
            fromStationId: 'a',
            toStationId: 'b',
            fromNodeId: 'n1',
            toNodeId: 'n2',
            edgeId: 'e1',
            lineId: 'l1',
            serviceClass: 'SUBWAY',
            servicePattern: 'LOCAL',
          ),
        ],
      ),
      RouteCandidateIdentity(
        query: query,
        legs: [
          RouteCandidateLegSignature(
            stepType: 'RIDE',
            fromStationId: 'x',
            toStationId: 'b',
            fromNodeId: 'n1',
            toNodeId: 'n2',
            edgeId: 'e1',
            lineId: 'l1',
            serviceClass: 'SUBWAY',
            servicePattern: 'LOCAL',
          ),
        ],
      ),
      RouteCandidateIdentity(
        query: query,
        legs: [
          RouteCandidateLegSignature(
            stepType: 'RIDE',
            fromStationId: 'a',
            toStationId: 'x',
            fromNodeId: 'n1',
            toNodeId: 'n2',
            edgeId: 'e1',
            lineId: 'l1',
            serviceClass: 'SUBWAY',
            servicePattern: 'LOCAL',
          ),
        ],
      ),
      RouteCandidateIdentity(
        query: query,
        legs: [
          RouteCandidateLegSignature(
            stepType: 'RIDE',
            fromStationId: 'a',
            toStationId: 'b',
            fromNodeId: 'n2',
            toNodeId: 'n1',
            edgeId: 'e1',
            lineId: 'l1',
            serviceClass: 'SUBWAY',
            servicePattern: 'LOCAL',
          ),
        ],
      ),
      RouteCandidateIdentity(
        query: query,
        legs: [
          RouteCandidateLegSignature(
            stepType: 'RIDE',
            fromStationId: 'a',
            toStationId: 'b',
            fromNodeId: 'n1',
            toNodeId: 'n2',
            edgeId: 'e1',
            lineId: 'l1',
            serviceClass: 'ITX_CHEONGCHUN',
            servicePattern: 'LOCAL',
          ),
        ],
      ),
      RouteCandidateIdentity(
        query: query,
        legs: [
          RouteCandidateLegSignature(
            stepType: 'RIDE',
            fromStationId: 'a',
            toStationId: 'b',
            fromNodeId: 'n1',
            toNodeId: 'n2',
            edgeId: 'e1',
            lineId: 'l1',
            serviceClass: 'SUBWAY',
            servicePattern: 'EXPRESS',
          ),
        ],
      ),
      RouteCandidateIdentity(
        query: query,
        legs: [
          RouteCandidateLegSignature(
            stepType: 'RIDE',
            fromStationId: 'a',
            toStationId: 'b',
            fromNodeId: 'n1',
            toNodeId: 'n2',
            edgeId: 'e2',
            lineId: 'l1',
            serviceClass: 'SUBWAY',
            servicePattern: 'LOCAL',
          ),
        ],
      ),
      RouteCandidateIdentity(
        query: query,
        legs: [
          RouteCandidateLegSignature(
            stepType: 'RIDE',
            fromStationId: 'a',
            toStationId: 'b',
            fromNodeId: 'n1',
            toNodeId: 'n2',
            edgeId: 'e1',
            lineId: 'l2',
            serviceClass: 'SUBWAY',
            servicePattern: 'LOCAL',
          ),
        ],
      ),
      RouteCandidateIdentity(
        query: query,
        legs: [
          RouteCandidateLegSignature(
            stepType: 'RIDE',
            fromStationId: 'a',
            toStationId: 'b',
            fromNodeId: 'n1',
            toNodeId: 'n2',
            edgeId: 'e1',
            lineId: 'l1',
            serviceClass: 'ITX_CHEONGCHUN',
            servicePattern: 'EXPRESS',
          ),
        ],
      ),
    ];
    for (final variant in variants) {
      expect(first.value, isNot(variant.value));
    }
    final twoLegs = RouteCandidateIdentity(
      query: query,
      legs: [
        RouteCandidateLegSignature(
          stepType: 'RIDE',
          fromStationId: 'a',
          toStationId: 'b',
        ),
        RouteCandidateLegSignature(
          stepType: 'WALK',
          fromStationId: 'b',
          toStationId: 'c',
        ),
      ],
    );
    final reversed = RouteCandidateIdentity(
      query: query,
      legs: [
        RouteCandidateLegSignature(
          stepType: 'WALK',
          fromStationId: 'b',
          toStationId: 'c',
        ),
        RouteCandidateLegSignature(
          stepType: 'RIDE',
          fromStationId: 'a',
          toStationId: 'b',
        ),
      ],
    );
    expect(twoLegs.value, isNot(reversed.value));
    expect(
      () => RouteCandidateIdentity(query: query, legs: const []),
      throwsArgumentError,
    );
  });

  test(
    'V2 candidate identity excludes provider, time, objective tags, and labels',
    () {
      final query = RouteQueryIdentity(
        originStationId: 'a',
        destinationStationId: 'b',
        mobilityType: 'STANDARD',
        constraintMode: 'PREFER_STEP_FREE',
        transportScope: 'SUBWAY',
        objective: 'FASTEST',
      );
      final first = RouteSearchResult.fromV2(
        _v2Result('2026-07-01T09:00:00Z', 'provider-itinerary-a', const [
          'FASTEST',
        ]),
        queryIdentity: query,
      );
      final second = RouteSearchResult.fromV2(
        _v2Result('2026-08-01T09:00:00Z', 'provider-itinerary-b', const [
          'FASTEST',
          'FEWEST_TRANSFERS',
        ]),
        queryIdentity: query,
      );
      expect(
        first.candidateIdentity!.canonicalBytes,
        second.candidateIdentity!.canonicalBytes,
      );
      expect(first.candidateIdentity!.value, second.candidateIdentity!.value);
      expect(
        first
            .withDisplayLabels(
              originStationName: '표시 A',
              destinationStationName: '표시 B',
              lineName: '표시 노선',
              etaSource: 'PLANNED',
            )
            .candidateIdentity!
            .value,
        first.candidateIdentity!.value,
      );
    },
  );

  test(
    'V2 blocked itinerary with raw empty legs keeps no candidate identity',
    () {
      final query = RouteQueryIdentity(
        originStationId: 'a',
        destinationStationId: 'b',
        mobilityType: 'STANDARD',
        constraintMode: 'PREFER_STEP_FREE',
        transportScope: 'SUBWAY',
        objective: 'FASTEST',
      );
      final result = RouteSearchResult.fromV2(
        _v2Result(
          '2026-07-01T09:00:00Z',
          'blocked-provider-id',
          const ['FASTEST'],
          status: 'BLOCKED',
          legs: const [],
        ),
        queryIdentity: query,
      );
      expect(result.status, 'BLOCKED');
      expect(result.candidateIdentity, isNull);
    },
  );
}

List<int> utf8Bytes(String value) => utf8.encode(value);

RouteSearchV2Result _v2Result(
  String departureTime,
  String itineraryId,
  List<String> tags, {
  String status = 'FOUND',
  List<RouteSearchV2Leg>? legs,
}) => RouteSearchV2Result(
  contractVersion: 'v2',
  originStationId: 'a',
  destinationStationId: 'b',
  departureTime: departureTime,
  mobilityType: 'STANDARD',
  constraintMode: 'PREFER_STEP_FREE',
  useRealtime: true,
  maxTransfers: 3,
  alternativeCount: 3,
  statuses: const ['BLOCKED'],
  itineraries: [
    RouteSearchV2Itinerary(
      itineraryId: itineraryId,
      status: status,
      plannedArrivalTime: '2026-07-01T09:10:00Z',
      realtimeArrivalTime: null,
      etaSource: 'PLANNED',
      etaConfidence: 'HIGH',
      durationSeconds: 600,
      transferCount: 0,
      walkingDistanceMeters: 0,
      accessibilityRisk: _risk,
      legs: legs ?? [_leg],
      commercialEtaEligible: false,
      objectiveTags: tags,
    ),
  ],
);

const _risk = RouteSearchV2AccessibilityRisk(
  stairCount: 0,
  unknownAccessibilityCount: 0,
  generatedConnectorCount: 0,
  staleDataCount: 0,
  lowConfidenceCount: 0,
  unavailableFacilityCount: 0,
  riskLevel: 'LOW',
  reasonCodes: [],
  level: 'LOW',
  reasons: [],
);
const _leg = RouteSearchV2Leg(
  legType: 'RIDE',
  fromStationId: 'a',
  toStationId: 'b',
  fromNodeId: 'n1',
  toNodeId: 'n2',
  lineId: 'l1',
  tripId: 'trip',
  trainNo: 'train',
  plannedDepartureTime: '2026-07-01T09:00:00Z',
  realtimeDepartureTime: null,
  plannedArrivalTime: '2026-07-01T09:10:00Z',
  realtimeArrivalTime: null,
  waitTimeSeconds: 0,
  slackSeconds: 0,
  durationSeconds: 600,
  distanceMeters: 0,
  etaSource: 'PLANNED',
  confidence: 'HIGH',
  accessibilityRisk: _risk,
  serviceClass: 'SUBWAY',
  servicePattern: 'LOCAL',
);
