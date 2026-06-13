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
    final credentialStore = MemoryAnonymousAuthCredentialStore();
    final session = AnonymousAuthSession(
      repository: repository,
      credentialStore: credentialStore,
    );

    final firstHeader = await session.authorizationHeader();
    final secondHeader = await session.authorizationHeader();

    expect(repository.issueCount, 1);
    expect(credentialStore.saveCount, 1);
    expect(firstHeader, secondHeader);
    expect(
      firstHeader,
      'Basic ${base64Encode(utf8.encode('anonymous-user-1:user-test-password'))}',
    );
  });

  test('익명 인증 세션은 저장된 인증 정보를 먼저 사용한다', () async {
    final repository = FakeAnonymousAuthRepository();
    final credentialStore = MemoryAnonymousAuthCredentialStore(
      const AnonymousAuthCredentials(
        userId: 'stored-anonymous-user',
        password: 'stored-password',
      ),
    );
    final session = AnonymousAuthSession(
      repository: repository,
      credentialStore: credentialStore,
    );

    final header = await session.authorizationHeader();

    expect(repository.issueCount, 0);
    expect(credentialStore.readCount, 1);
    expect(credentialStore.saveCount, 0);
    expect(
      header,
      'Basic ${base64Encode(utf8.encode('stored-anonymous-user:stored-password'))}',
    );
  });

  test('익명 인증 세션은 발급한 인증 정보를 저장해 재시작 후 재사용한다', () async {
    final credentialStore = MemoryAnonymousAuthCredentialStore();
    final firstRepository = FakeAnonymousAuthRepository();
    final firstSession = AnonymousAuthSession(
      repository: firstRepository,
      credentialStore: credentialStore,
    );

    final firstHeader = await firstSession.authorizationHeader();
    final secondRepository = FakeAnonymousAuthRepository(
      userId: 'new-anonymous-user',
      password: 'new-password',
    );
    final secondSession = AnonymousAuthSession(
      repository: secondRepository,
      credentialStore: credentialStore,
    );
    final secondHeader = await secondSession.authorizationHeader();

    expect(firstRepository.issueCount, 1);
    expect(secondRepository.issueCount, 0);
    expect(credentialStore.saveCount, 1);
    expect(secondHeader, firstHeader);
  });

  test('익명 인증 세션은 인증 실패 후 저장된 인증 정보를 지우고 다시 발급한다', () async {
    final credentialStore = MemoryAnonymousAuthCredentialStore(
      const AnonymousAuthCredentials(
        userId: 'stale-anonymous-user',
        password: 'stale-password',
      ),
    );
    final repository = FakeAnonymousAuthRepository(
      userId: 'fresh-anonymous-user',
      password: 'fresh-password',
    );
    final session = AnonymousAuthSession(
      repository: repository,
      credentialStore: credentialStore,
    );

    final staleHeader = await session.authorizationHeader();
    await session.invalidateAuthorization();
    final freshHeader = await session.authorizationHeader();

    expect(
      staleHeader,
      'Basic ${base64Encode(utf8.encode('stale-anonymous-user:stale-password'))}',
    );
    expect(
      freshHeader,
      'Basic ${base64Encode(utf8.encode('fresh-anonymous-user:fresh-password'))}',
    );
    expect(repository.issueCount, 1);
    expect(credentialStore.clearCount, 1);
    expect(credentialStore.saveCount, 1);
    expect(credentialStore.credentials?.userId, 'fresh-anonymous-user');
  });

  test('익명 인증 세션은 동시에 요청해도 발급 요청을 하나만 보낸다', () async {
    final repository = FakeAnonymousAuthRepository(issueDelay: Duration.zero);
    final credentialStore = MemoryAnonymousAuthCredentialStore();
    final session = AnonymousAuthSession(
      repository: repository,
      credentialStore: credentialStore,
    );

    final headers = await Future.wait([
      session.authorizationHeader(),
      session.authorizationHeader(),
      session.authorizationHeader(),
    ]);

    expect(repository.issueCount, 1);
    expect(credentialStore.readCount, 1);
    expect(credentialStore.saveCount, 1);
    expect(headers.toSet(), hasLength(1));
  });

  test('익명 인증 API 저장소는 원격 HTTP 주소로 인증 정보를 보내지 않는다', () async {
    for (final baseUri in [
      Uri.parse('http://example.com'),
      Uri.parse('http://127.example.com'),
    ]) {
      final httpClient = NetworkFailingHttpClient();
      final repository = AnonymousAuthApiRepository(
        baseUri: baseUri,
        httpClient: httpClient,
      );

      expect(
        repository.issueAnonymousUser,
        throwsA(isA<AnonymousAuthException>()),
      );
      expect(httpClient.postUrlCalled, isFalse);
    }
  });

  test('익명 인증 API 저장소는 릴리즈 가정에서 에뮬레이터 HTTP 별칭을 막는다', () async {
    final httpClient = NetworkFailingHttpClient();
    final repository = AnonymousAuthApiRepository(
      baseUri: Uri.parse('http://10.0.2.2:8080'),
      httpClient: httpClient,
      allowAndroidEmulatorHttp: false,
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
    this.userId = 'anonymous-user-1',
    this.password = 'user-test-password',
  });

  final Duration issueDelay;
  final String userId;
  final String password;
  int issueCount = 0;

  @override
  Future<AnonymousAuthCredentials> issueAnonymousUser() async {
    issueCount++;
    await Future<void>.delayed(issueDelay);
    return AnonymousAuthCredentials(userId: userId, password: password);
  }
}

class MemoryAnonymousAuthCredentialStore
    implements AnonymousAuthCredentialStore {
  MemoryAnonymousAuthCredentialStore([this.credentials]);

  AnonymousAuthCredentials? credentials;
  int readCount = 0;
  int saveCount = 0;
  int clearCount = 0;

  @override
  Future<AnonymousAuthCredentials?> readCredentials() async {
    readCount++;
    return credentials;
  }

  @override
  Future<void> saveCredentials(AnonymousAuthCredentials credentials) async {
    saveCount++;
    this.credentials = credentials;
  }

  @override
  Future<void> clearCredentials() async {
    clearCount++;
    credentials = null;
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
