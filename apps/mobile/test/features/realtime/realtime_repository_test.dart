import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/features/realtime/realtime_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('realtime API 저장소는 fresh 도착 정보를 파싱한다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      expect(request.uri.path, '/api/v1/realtime/arrivals');
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'status': 'FRESH',
              'receivedAt': '2026-06-26T08:00:01Z',
              'arrivals': [
                {
                  'lineId': '4',
                  'stationName': '상록수',
                  'destination': '당고개',
                  'direction': '상행',
                  'trainNo': '4123',
                  'etaSeconds': 180,
                  'message': '3분 후',
                  'positionMessage': '전역 출발',
                  'providerReceivedAt': '2026-06-26T08:00:00Z',
                },
              ],
            },
          }),
        )
        ..close();
    });
    final repository = RealtimeApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final snapshot = await repository.arrivals(
      const RealtimeStationQuery(
        stationId: 'station-sangnoksu',
        lineId: '4',
        stationQueryName: '상록수',
      ),
    );

    expect(snapshot.status, RealtimeSnapshotStatus.fresh);
    expect(snapshot.arrivals.single.etaSeconds, 180);
    expect(snapshot.summaryText, '상록수 3분 후');
  });

  test('realtime API 저장소는 unsupported 응답을 안전한 상태로 파싱한다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'status': 'UNSUPPORTED',
              'fallbackCode': 'UNSUPPORTED_REGION',
              'message': '서울 TOPIS 실시간 지원 범위 밖입니다.',
              'arrivals': <Object?>[],
            },
          }),
        )
        ..close();
    });
    final repository = RealtimeApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final snapshot = await repository.arrivals(
      const RealtimeStationQuery(
        stationId: 'station-outside',
        lineId: 'other',
        stationQueryName: '외부역',
      ),
    );

    expect(snapshot.status, RealtimeSnapshotStatus.unsupported);
    expect(snapshot.message, '서울 TOPIS 실시간 지원 범위 밖입니다.');
  });

  test('realtime API 저장소는 비어 있는 선택 도착 표시 필드를 허용한다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'status': 'FRESH',
              'receivedAt': '2026-06-26T08:00:01Z',
              'arrivals': [
                {
                  'lineId': '4',
                  'stationName': '상록수',
                  'destination': '오이도',
                  'direction': '',
                  'trainNo': '',
                  'etaSeconds': null,
                  'message': '',
                },
              ],
            },
          }),
        )
        ..close();
    });
    final repository = RealtimeApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final snapshot = await repository.arrivals(
      const RealtimeStationQuery(
        stationId: 'station-sangnoksu',
        lineId: '4',
        stationQueryName: '상록수',
      ),
    );

    expect(snapshot.status, RealtimeSnapshotStatus.fresh);
    expect(snapshot.arrivals.single.direction, '');
    expect(snapshot.arrivals.single.trainNo, '');
    expect(snapshot.arrivals.single.message, '');
  });
}
