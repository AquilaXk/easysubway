import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/anonymous_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('익명 인증 API 저장소는 발급 응답을 파싱한다', () async {
    late String requestedMethod;
    late Uri requestedUri;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestedMethod = request.method;
      requestedUri = request.uri;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'userId': 'anonymous-user-1',
              'password': 'user-test-password',
              'authType': 'BASIC',
              'anonymous': true,
              'createdAt': '2026-06-13T10:00:00',
            },
          }),
        )
        ..close();
    });

    final repository = AnonymousAuthApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final credentials = await repository.issueAnonymousUser();

    expect(requestedMethod, 'POST');
    expect(requestedUri.path, '/api/v1/auth/anonymous');
    expect(credentials.userId, 'anonymous-user-1');
    expect(credentials.password, 'user-test-password');
    expect(credentials.authorizationHeader, startsWith('Basic '));
  });

  test('익명 인증 세션은 한 번 발급한 Basic 헤더를 재사용한다', () async {
    final repository = FakeAnonymousAuthRepository();
    final session = AnonymousAuthSession(repository: repository);

    final firstHeader = await session.authorizationHeader();
    final secondHeader = await session.authorizationHeader();

    expect(repository.issueCount, 1);
    expect(firstHeader, secondHeader);
    expect(
      firstHeader,
      'Basic ${base64Encode(utf8.encode('anonymous-user-1:user-test-password'))}',
    );
  });

  test('익명 인증 세션은 동시에 요청해도 발급 요청을 하나만 보낸다', () async {
    final repository = FakeAnonymousAuthRepository(issueDelay: Duration.zero);
    final session = AnonymousAuthSession(repository: repository);

    final headers = await Future.wait([
      session.authorizationHeader(),
      session.authorizationHeader(),
      session.authorizationHeader(),
    ]);

    expect(repository.issueCount, 1);
    expect(headers.toSet(), hasLength(1));
  });

  test('익명 인증 API 저장소는 원격 HTTP 주소로 인증 정보를 보내지 않는다', () async {
    final httpClient = NetworkFailingHttpClient();
    final repository = AnonymousAuthApiRepository(
      baseUri: Uri.parse('http://example.com'),
      httpClient: httpClient,
    );

    expect(
      repository.issueAnonymousUser,
      throwsA(isA<AnonymousAuthException>()),
    );
    expect(httpClient.postUrlCalled, isFalse);
  });
}

class FakeAnonymousAuthRepository implements AnonymousAuthRepository {
  FakeAnonymousAuthRepository({
    this.issueDelay = const Duration(milliseconds: 10),
  });

  final Duration issueDelay;
  int issueCount = 0;

  @override
  Future<AnonymousAuthCredentials> issueAnonymousUser() async {
    issueCount++;
    await Future<void>.delayed(issueDelay);
    return const AnonymousAuthCredentials(
      userId: 'anonymous-user-1',
      password: 'user-test-password',
    );
  }
}

class NetworkFailingHttpClient implements HttpClient {
  bool postUrlCalled = false;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    postUrlCalled = true;
    throw StateError('network should not be called');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
