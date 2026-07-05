import 'package:easysubway_mobile/route_hedge_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('route hedge labels 단일 사전(#1577)', () {
    test('불확실성 원인은 의미 기준 3종 + 일반으로만 수렴한다', () {
      expect(
        routeUncertaintyHedgeLabel('STAIR_ONLY_ACCESS_UNKNOWN'),
        routeHedgeStepFreeUnknown,
      );
      expect(
        routeUncertaintyHedgeLabel('ACCESSIBILITY_STATE_UNKNOWN'),
        routeHedgeAccessibilityUnknown,
      );
      // 경로 그래프 미확인과 생성 연결 미확인은 같은 '경로 연결' 문구 한 벌로 모은다.
      expect(
        routeUncertaintyHedgeLabel('ROUTE_GRAPH_UNKNOWN'),
        routeHedgeConnectivityUnknown,
      );
      expect(
        routeUncertaintyHedgeLabel('GENERATED_CONNECTOR_UNVERIFIED'),
        routeHedgeConnectivityUnknown,
      );
      // 특정할 수 없는 코드는 일반 문구로.
      expect(
        routeUncertaintyHedgeLabel('UNKNOWN_CODE'),
        routeHedgeGenericUnknown,
      );

      // 불확실성 헤지 문구는 정확히 4벌(3종 + 일반)뿐이다.
      final all = {
        routeHedgeStepFreeUnknown,
        routeHedgeAccessibilityUnknown,
        routeHedgeConnectivityUnknown,
        routeHedgeGenericUnknown,
      };
      expect(all.length, 4);
    });

    test('부드러운 진행형으로 안내해 부정·면책 톤을 낮춘다', () {
      for (final label in [
        routeHedgeStepFreeUnknown,
        routeHedgeAccessibilityUnknown,
        routeHedgeConnectivityUnknown,
        routeHedgeGenericUnknown,
      ]) {
        expect(label, endsWith('확인하고 있어요.'), reason: label);
        expect(label, isNot(contains('알 수 없')), reason: label);
        expect(label, isNot(contains('못했')), reason: label);
      }
    });

    test('사실성 주의는 헤지로 흡수하지 않고 그대로 유지한다', () {
      expect(routeWarningLabel('STAIR_ONLY_ACCESS'), '계단 포함 구간이 있습니다.');
      expect(
        routeWarningLabel('STALE_ACCESSIBILITY_DATA'),
        '시설 상태 안내가 오래됐을 수 있어요.',
      );
      // 불확실성 계열 코드는 헤지 사전으로 위임된다.
      expect(
        routeWarningLabel('ACCESSIBILITY_STATE_UNKNOWN'),
        routeHedgeAccessibilityUnknown,
      );
      expect(routeWarningLabel('SOMETHING_ELSE'), routeHedgeGenericUnknown);
    });
  });
}
