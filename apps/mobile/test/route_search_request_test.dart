import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toV2Json은 mobilityPreset이 있으면 body에 싣고 mobilityType도 함께 보낸다', () {
    const request = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'WHEELCHAIR',
      mobilityPreset: 'STEP_FREE',
    );

    final body = request.toV2Json();

    expect(body['mobilityPreset'], 'STEP_FREE');
    expect(body['mobilityType'], 'WHEELCHAIR');
    expect(body['constraintMode'], 'STRICT_STEP_FREE');
  });

  test('toV2Json은 mobilityPreset이 없으면 키를 넣지 않는다', () {
    const request = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'SENIOR',
    );

    final body = request.toV2Json();

    expect(body.containsKey('mobilityPreset'), isFalse);
    expect(body['mobilityType'], 'SENIOR');
  });

  test('STANDARD 프리셋은 strict가 아닌 PREFER_STEP_FREE로 전송된다', () {
    const request = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'STANDARD',
      mobilityPreset: 'STANDARD',
    );

    final body = request.toV2Json();

    expect(body['mobilityPreset'], 'STANDARD');
    expect(body['mobilityType'], 'STANDARD');
    expect(body['constraintMode'], 'PREFER_STEP_FREE');
  });

  test('toJson(v1)에는 mobilityPreset을 넣지 않는다', () {
    const request = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'WHEELCHAIR',
      mobilityPreset: 'STEP_FREE',
    );

    expect(request.toJson().containsKey('mobilityPreset'), isFalse);
  });

  test('toV2Json은 기본 objective로 FASTEST를 싣는다', () {
    const request = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'STANDARD',
    );

    expect(request.toV2Json()['objective'], 'FASTEST');
  });

  test('toV2Json은 선택한 objective를 서버 문자열로 싣는다', () {
    const request = RouteSearchRequest(
      originStationId: 'station-a',
      destinationStationId: 'station-b',
      mobilityType: 'STANDARD',
      objective: RouteObjective.fewestTransfers,
    );

    expect(request.toV2Json()['objective'], 'FEWEST_TRANSFERS');
  });

  test('요청 serialization에는 servicePattern·expressOnly를 싣지 않는다', () {
    for (final objective in RouteObjective.values) {
      for (final scope in RouteTransportScope.values) {
        final request = RouteSearchRequest(
          originStationId: 'station-a',
          destinationStationId: 'station-b',
          mobilityType: 'STANDARD',
          objective: objective,
          transportScope: scope,
        );
        final body = request.toV2Json();
        expect(body.containsKey('servicePattern'), isFalse);
        expect(body.containsKey('expressOnly'), isFalse);
      }
    }
  });

  test('네 조합(objective × scope)은 요청 필드에 그대로 보존된다', () {
    final expectations = {
      (RouteObjective.fastest, RouteTransportScope.subway): 'FASTEST',
      (RouteObjective.fewestTransfers, RouteTransportScope.subway):
          'FEWEST_TRANSFERS',
      (RouteObjective.fastest, RouteTransportScope.subwayAndItxCheongchun):
          'FASTEST',
      (
        RouteObjective.fewestTransfers,
        RouteTransportScope.subwayAndItxCheongchun,
      ): 'FEWEST_TRANSFERS',
    };
    expectations.forEach((combo, expectedObjective) {
      final (objective, scope) = combo;
      final request = RouteSearchRequest(
        originStationId: 'station-a',
        destinationStationId: 'station-b',
        mobilityType: 'STANDARD',
        objective: objective,
        transportScope: scope,
      );
      expect(request.objective.serverValue, expectedObjective);
      expect(request.transportScope, scope);
      expect(request.toV2Json()['objective'], expectedObjective);
    });
  });
}
