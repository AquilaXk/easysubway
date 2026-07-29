import 'dart:convert';

import 'package:easysubway_mobile/features/routes/domain/route_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
  });

  test('query identity changes for each route query input but excludes raw search data', () {
    final base = RouteQueryIdentity(
      originStationId: 'a', destinationStationId: 'b', mobilityType: 'STANDARD',
      constraintMode: 'PREFER_STEP_FREE', transportScope: 'SUBWAY', objective: 'FASTEST',
    );
    final variants = [
      RouteQueryIdentity(originStationId: 'x', destinationStationId: 'b', mobilityType: 'STANDARD', constraintMode: 'PREFER_STEP_FREE', transportScope: 'SUBWAY', objective: 'FASTEST'),
      RouteQueryIdentity(originStationId: 'a', destinationStationId: 'x', mobilityType: 'STANDARD', constraintMode: 'PREFER_STEP_FREE', transportScope: 'SUBWAY', objective: 'FASTEST'),
      RouteQueryIdentity(originStationId: 'a', destinationStationId: 'b', mobilityType: 'SENIOR', constraintMode: 'PREFER_STEP_FREE', transportScope: 'SUBWAY', objective: 'FASTEST'),
      RouteQueryIdentity(originStationId: 'a', destinationStationId: 'b', mobilityType: 'STANDARD', constraintMode: 'PREFER_STEP_FREE', waypointStationId: 'w', transportScope: 'SUBWAY', objective: 'FASTEST'),
      RouteQueryIdentity(originStationId: 'a', destinationStationId: 'b', mobilityType: 'STANDARD', constraintMode: 'PREFER_STEP_FREE', mobilityPreset: 'STEP_FREE', transportScope: 'SUBWAY', objective: 'FASTEST'),
      RouteQueryIdentity(originStationId: 'a', destinationStationId: 'b', mobilityType: 'STANDARD', constraintMode: 'STRICT_STEP_FREE', transportScope: 'SUBWAY', objective: 'FASTEST'),
      RouteQueryIdentity(originStationId: 'a', destinationStationId: 'b', mobilityType: 'STANDARD', constraintMode: 'PREFER_STEP_FREE', transportScope: 'SUBWAY_AND_ITX_CHEONGCHUN', objective: 'FASTEST'),
      RouteQueryIdentity(originStationId: 'a', destinationStationId: 'b', mobilityType: 'STANDARD', constraintMode: 'PREFER_STEP_FREE', transportScope: 'SUBWAY', objective: 'FEWEST_TRANSFERS'),
    ];
    for (final variant in variants) {
      expect(variant, isNot(base));
      expect(variant.value, isNot(base.value));
    }
    final canonicalText = utf8.decode(base.canonicalBytes);
    expect(canonicalText, isNot(contains('상록수 검색어')));
    expect(canonicalText, isNot(contains('37.123')));
    expect(canonicalText, isNot(contains('secret-token')));
    final ambiguousLeft = RouteQueryIdentity(originStationId: 'ab', destinationStationId: 'c', mobilityType: 'STANDARD', constraintMode: 'PREFER_STEP_FREE', transportScope: 'SUBWAY', objective: 'FASTEST');
    final ambiguousRight = RouteQueryIdentity(originStationId: 'a', destinationStationId: 'bc', mobilityType: 'STANDARD', constraintMode: 'PREFER_STEP_FREE', transportScope: 'SUBWAY', objective: 'FASTEST');
    expect(ambiguousLeft.value, isNot(ambiguousRight.value));
    expect(base.value, isNot(RouteQueryIdentity(originStationId: 'local-a', destinationStationId: 'online-b', mobilityType: 'STANDARD', constraintMode: 'PREFER_STEP_FREE', transportScope: 'SUBWAY', objective: 'FASTEST').value));
  });

  test('candidate identity is ordered and ignores display-only provider data', () {
    final query = RouteQueryIdentity(originStationId: 'a', destinationStationId: 'b', mobilityType: 'STANDARD', constraintMode: 'PREFER_STEP_FREE', transportScope: 'SUBWAY', objective: 'FASTEST');
    final first = RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'a', toStationId: 'b', fromNodeId: 'n1', toNodeId: 'n2', edgeId: 'e1', lineId: 'l1', serviceClass: 'SUBWAY', servicePattern: 'LOCAL')]);
    expect(first.canonicalBytes, utf8.encode('["route-candidate-v1",["route-query-v1","a","b",null,"STANDARD",null,"PREFER_STEP_FREE","SUBWAY","FASTEST"],[["RIDE","a","b","n1","n2","e1","l1","SUBWAY","LOCAL"]]]'));
    expect(first.value, 'rc:v1:aeb259ab45a445856f0277476cd61b04bf225036003f7a06e28faa4e4409e3aa');
    final variants = [
      RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'WALK', fromStationId: 'a', toStationId: 'b', fromNodeId: 'n1', toNodeId: 'n2', edgeId: 'e1', lineId: 'l1', serviceClass: 'SUBWAY', servicePattern: 'LOCAL')]),
      RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'x', toStationId: 'b', fromNodeId: 'n1', toNodeId: 'n2', edgeId: 'e1', lineId: 'l1', serviceClass: 'SUBWAY', servicePattern: 'LOCAL')]),
      RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'a', toStationId: 'x', fromNodeId: 'n1', toNodeId: 'n2', edgeId: 'e1', lineId: 'l1', serviceClass: 'SUBWAY', servicePattern: 'LOCAL')]),
      RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'a', toStationId: 'b', fromNodeId: 'n2', toNodeId: 'n1', edgeId: 'e1', lineId: 'l1', serviceClass: 'SUBWAY', servicePattern: 'LOCAL')]),
      RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'a', toStationId: 'b', fromNodeId: 'n1', toNodeId: 'n2', edgeId: 'e1', lineId: 'l1', serviceClass: 'ITX_CHEONGCHUN', servicePattern: 'LOCAL')]),
      RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'a', toStationId: 'b', fromNodeId: 'n1', toNodeId: 'n2', edgeId: 'e1', lineId: 'l1', serviceClass: 'SUBWAY', servicePattern: 'EXPRESS')]),
      RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'a', toStationId: 'b', fromNodeId: 'n1', toNodeId: 'n2', edgeId: 'e2', lineId: 'l1', serviceClass: 'SUBWAY', servicePattern: 'LOCAL')]),
      RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'a', toStationId: 'b', fromNodeId: 'n1', toNodeId: 'n2', edgeId: 'e1', lineId: 'l2', serviceClass: 'SUBWAY', servicePattern: 'LOCAL')]),
      RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'a', toStationId: 'b', fromNodeId: 'n1', toNodeId: 'n2', edgeId: 'e1', lineId: 'l1', serviceClass: 'ITX_CHEONGCHUN', servicePattern: 'EXPRESS')]),
    ];
    for (final variant in variants) { expect(first.value, isNot(variant.value)); }
    final twoLegs = RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'a', toStationId: 'b'), RouteCandidateLegSignature(stepType: 'WALK', fromStationId: 'b', toStationId: 'c')]);
    final reversed = RouteCandidateIdentity(query: query, legs: [RouteCandidateLegSignature(stepType: 'WALK', fromStationId: 'b', toStationId: 'c'), RouteCandidateLegSignature(stepType: 'RIDE', fromStationId: 'a', toStationId: 'b')]);
    expect(twoLegs.value, isNot(reversed.value));
    expect(() => RouteCandidateIdentity(query: query, legs: const []), throwsArgumentError);
  });
}

List<int> utf8Bytes(String value) => utf8.encode(value);
