import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:easysubway_mobile/route_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('RouteSearchOnlineException.response uses contract mapping', () {
    final error = RouteSearchOnlineException.response(
      const ApiResponse(
        statusCode: 429,
        jsonBody: {
          'success': false,
          'code': 'ROUTE_RATE_LIMITED',
          'correlationId': 'corr-route-1',
        },
      ),
    );
    expect(error.message, '잠시 후 다시 시도');
    expect(error.failureReason, 'ROUTE_RATE_LIMITED');
    expect(error.correlationId, 'corr-route-1');
  });

  test('unknown server code uses category fallback message', () {
    final error = RouteSearchOnlineException.response(
      const ApiResponse(
        statusCode: 503,
        jsonBody: {
          'success': false,
          'code': 'SOME_NEW_DEP_CODE',
          'correlationId': 'corr-dep',
        },
      ),
    );
    expect(error.message, '외부 서비스를 잠시 사용할 수 없어요. 잠시 후 다시 시도해 주세요.');
    expect(error.failureReason, 'SOME_NEW_DEP_CODE');
    expect(error.correlationId, 'corr-dep');
  });
}
