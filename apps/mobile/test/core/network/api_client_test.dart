import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ApiClient는 GET 요청에 공통 header와 custom header를 적용한다', () async {
    late String requestedMethod;
    late Uri requestedUri;
    late String? acceptHeader;
    late String? receiptTokenHeader;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestedMethod = request.method;
      requestedUri = request.uri;
      acceptHeader = request.headers.value(HttpHeaders.acceptHeader);
      receiptTokenHeader = request.headers.value(
        'X-Easysubway-Report-Receipt-Token',
      );
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {'id': 'report-1', 'status': 'ACCEPTED'},
          }),
        )
        ..close();
    });

    final client = ApiClient(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final response = await client.getJson(
      '/api/v1/reports/report-1',
      headers: const {'X-Easysubway-Report-Receipt-Token': 'receipt-token-1'},
    );

    expect(requestedMethod, 'GET');
    expect(requestedUri.path, '/api/v1/reports/report-1');
    expect(acceptHeader, ContentType.json.mimeType);
    expect(receiptTokenHeader, 'receipt-token-1');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.jsonBody, {
      'success': true,
      'data': {'id': 'report-1', 'status': 'ACCEPTED'},
    });
  });

  test('ApiClient는 POST 요청에 JSON body와 공통 header를 적용한다', () async {
    late String requestedMethod;
    late Uri requestedUri;
    late String? acceptHeader;
    late ContentType? contentType;
    late Map<String, Object?> requestBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestedMethod = request.method;
      requestedUri = request.uri;
      acceptHeader = request.headers.value(HttpHeaders.acceptHeader);
      contentType = request.headers.contentType;
      requestBody =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      request.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {'id': 'report-1'},
          }),
        );
      await request.response.close();
    });

    final client = ApiClient(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final response = await client.postJson(
      '/api/v1/reports',
      body: const {
        'stationId': 'station-sangnoksu',
        'description': '문이 열리지 않습니다.',
      },
    );

    expect(requestedMethod, 'POST');
    expect(requestedUri.path, '/api/v1/reports');
    expect(acceptHeader, ContentType.json.mimeType);
    expect(contentType?.mimeType, ContentType.json.mimeType);
    expect(requestBody['stationId'], 'station-sangnoksu');
    expect(requestBody['description'], '문이 열리지 않습니다.');
    expect(response.statusCode, HttpStatus.created);
    expect(response.jsonBody, {
      'success': true,
      'data': {'id': 'report-1'},
    });
  });

  test('ApiClient는 PUT 요청에 JSON body와 공통 header를 적용한다', () async {
    late String requestedMethod;
    late Uri requestedUri;
    late String? acceptHeader;
    late String? authorizationHeader;
    late ContentType? contentType;
    late Map<String, Object?> requestBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestedMethod = request.method;
      requestedUri = request.uri;
      acceptHeader = request.headers.value(HttpHeaders.acceptHeader);
      authorizationHeader = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      contentType = request.headers.contentType;
      requestBody =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {'stationId': 'station-sangnoksu'},
          }),
        );
      await request.response.close();
    });

    final client = ApiClient(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final response = await client.putJson(
      '/api/v1/me/favorites/stations/station-sangnoksu',
      body: const {'source': 'station-detail'},
      headers: const {HttpHeaders.authorizationHeader: 'Basic token-1'},
    );

    expect(requestedMethod, 'PUT');
    expect(
      requestedUri.path,
      '/api/v1/me/favorites/stations/station-sangnoksu',
    );
    expect(acceptHeader, ContentType.json.mimeType);
    expect(authorizationHeader, 'Basic token-1');
    expect(contentType?.mimeType, ContentType.json.mimeType);
    expect(requestBody, {'source': 'station-detail'});
    expect(response.statusCode, HttpStatus.ok);
    expect(response.jsonBody, {
      'success': true,
      'data': {'stationId': 'station-sangnoksu'},
    });
  });

  test('ApiClient는 PUT bytes 요청에 body와 upload header를 적용한다', () async {
    late String requestedMethod;
    late Uri requestedUri;
    late String? checksumHeader;
    late ContentType? contentType;
    late int? contentLength;
    late List<int> requestBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestedMethod = request.method;
      requestedUri = request.uri;
      checksumHeader = request.headers.value('x-amz-checksum-sha256');
      contentType = request.headers.contentType;
      contentLength = request.headers.contentLength;
      requestBody = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) => bytes..addAll(chunk),
      );
      request.response.statusCode = HttpStatus.created;
      await request.response.close();
    });

    final client = ApiClient(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final response = await client.putBytes(
      Uri.parse('http://${server.address.host}:${server.port}/uploads/photo'),
      body: const [1, 2, 3, 4],
      contentType: ContentType('image', 'jpeg'),
      headers: const {'x-amz-checksum-sha256': 'checksum-1'},
    );

    expect(requestedMethod, 'PUT');
    expect(requestedUri.path, '/uploads/photo');
    expect(checksumHeader, 'checksum-1');
    expect(contentType?.mimeType, 'image/jpeg');
    expect(contentLength, 4);
    expect(requestBody, [1, 2, 3, 4]);
    expect(response.statusCode, HttpStatus.created);
    expect(response.isSuccess, isTrue);
  });

  test('ApiClient는 DELETE 요청에 공통 timeout과 JSON decode 경계를 적용한다', () async {
    late String requestedMethod;
    late Uri requestedUri;
    late String? acceptHeader;
    late String? authorizationHeader;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestedMethod = request.method;
      requestedUri = request.uri;
      acceptHeader = request.headers.value(HttpHeaders.acceptHeader);
      authorizationHeader = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {'userId': 'anonymous-user-1'},
          }),
        )
        ..close();
    });

    final client = ApiClient(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final response = await client.deleteJson(
      '/api/v1/me',
      headers: const {HttpHeaders.authorizationHeader: 'Bearer secret-token'},
    );

    expect(requestedMethod, 'DELETE');
    expect(requestedUri.path, '/api/v1/me');
    expect(acceptHeader, ContentType.json.mimeType);
    expect(authorizationHeader, 'Bearer secret-token');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.jsonBody, {
      'success': true,
      'data': {'userId': 'anonymous-user-1'},
    });
  });

  test('ApiClient 예외는 인증 토큰을 노출하지 않는다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write('not-json')
        ..close();
    });

    final client = ApiClient(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    await expectLater(
      client.deleteJson(
        '/api/v1/me',
        headers: const {
          HttpHeaders.authorizationHeader: 'Bearer sensitive-access-token',
        },
      ),
      throwsA(
        isA<ApiException>()
            .having(
              (error) => error.toString(),
              'error text',
              isNot(contains('sensitive-access-token')),
            )
            .having(
              (error) => error.toString(),
              'error text',
              isNot(contains('Bearer')),
            ),
      ),
    );
  });
}
