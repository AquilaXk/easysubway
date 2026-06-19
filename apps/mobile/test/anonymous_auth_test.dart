import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/anonymous_auth.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_secure_key_value_storage.dart';

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
              'accessToken': 'access-token-1',
              'refreshToken': 'refresh-token-1',
              'authType': 'BEARER',
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
    expect(credentials.accessToken, 'access-token-1');
    expect(credentials.refreshToken, 'refresh-token-1');
    expect(credentials.authorizationHeader, 'Bearer access-token-1');
  });

  test('익명 인증 세션은 한 번 발급한 Bearer 헤더를 재사용한다', () async {
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
    expect(firstHeader, 'Bearer access-token-1');
  });

  test('익명 인증 저장소는 secure storage 복원 실패 시 저장값을 지운다', () async {
    final storage = FakeSecureKeyValueStorage(
      readError: StateError('restored Android KeyStore value is invalid'),
    );
    final store = SecureAnonymousAuthCredentialStore(storage: storage);

    final credentials = await store.readCredentials();

    expect(credentials, isNull);
    expect(storage.deletedKeys, hasLength(1));
  });

  test('익명 인증 저장소는 secure storage 삭제 실패에도 null로 복구한다', () async {
    final storage = FakeSecureKeyValueStorage(
      readError: StateError('restored Android KeyStore value is invalid'),
      deleteError: StateError('secure storage delete failed'),
    );
    final store = SecureAnonymousAuthCredentialStore(storage: storage);

    final credentials = await store.readCredentials();

    expect(credentials, isNull);
    expect(storage.deletedKeys, isEmpty);
  });

  test('익명 인증 세션은 저장된 인증 정보를 먼저 사용한다', () async {
    final repository = FakeAnonymousAuthRepository();
    final credentialStore = MemoryAnonymousAuthCredentialStore(
      const AnonymousAuthCredentials(
        userId: 'stored-anonymous-user',
        accessToken: 'stored-access-token',
        refreshToken: 'stored-refresh-token',
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
    expect(header, 'Bearer stored-access-token');
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
      accessToken: 'new-access-token',
      refreshToken: 'new-refresh-token',
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

  test('익명 인증 세션은 인증 실패 후 refresh token으로 새 access token을 발급한다', () async {
    final credentialStore = MemoryAnonymousAuthCredentialStore(
      const AnonymousAuthCredentials(
        userId: 'stale-anonymous-user',
        accessToken: 'stale-access-token',
        refreshToken: 'stale-refresh-token',
      ),
    );
    final repository = FakeAnonymousAuthRepository(
      userId: 'fresh-anonymous-user',
      accessToken: 'fresh-access-token',
      refreshToken: 'fresh-refresh-token',
    );
    final session = AnonymousAuthSession(
      repository: repository,
      credentialStore: credentialStore,
    );

    final staleHeader = await session.authorizationHeader();
    await session.invalidateAuthorization();
    final freshHeader = await session.authorizationHeader();

    expect(staleHeader, 'Bearer stale-access-token');
    expect(freshHeader, 'Bearer fresh-access-token');
    expect(repository.issueCount, 0);
    expect(repository.refreshCount, 1);
    expect(repository.refreshedTokens, ['stale-refresh-token']);
    expect(credentialStore.clearCount, 0);
    expect(credentialStore.saveCount, 1);
    expect(credentialStore.credentials?.userId, 'fresh-anonymous-user');
  });

  test('익명 인증 세션은 삭제 요청에 사용한 인증 정보가 바뀌면 기존 인증 갱신을 실패 처리한다', () async {
    final credentialStore = MemoryAnonymousAuthCredentialStore(
      const AnonymousAuthCredentials(
        userId: 'stale-anonymous-user',
        accessToken: 'stale-access-token',
        refreshToken: 'stale-refresh-token',
      ),
    );
    final repository = FakeAnonymousAuthRepository(
      userId: 'fresh-anonymous-user',
      accessToken: 'fresh-access-token',
      refreshToken: 'fresh-refresh-token',
    );
    final session = AnonymousAuthSession(
      repository: repository,
      credentialStore: credentialStore,
    );

    final staleHeader = await session.authorizationHeader();
    await session.invalidateAuthorization();

    final refreshed = await session.refreshExistingAuthorization(staleHeader!);

    expect(refreshed, isFalse);
    expect(repository.refreshCount, 1);
    expect(
      credentialStore.credentials?.authorizationHeader,
      'Bearer fresh-access-token',
    );
  });

  test('익명 인증 세션은 삭제 요청에 사용한 인증 정보만 기존 인증 갱신한다', () async {
    final credentialStore = MemoryAnonymousAuthCredentialStore(
      const AnonymousAuthCredentials(
        userId: 'stale-anonymous-user',
        accessToken: 'stale-access-token',
        refreshToken: 'stale-refresh-token',
      ),
    );
    final repository = FakeAnonymousAuthRepository(
      userId: 'fresh-anonymous-user',
      accessToken: 'fresh-access-token',
      refreshToken: 'fresh-refresh-token',
    );
    final session = AnonymousAuthSession(
      repository: repository,
      credentialStore: credentialStore,
    );

    final staleHeader = await session.authorizationHeader();

    final refreshed = await session.refreshExistingAuthorization(staleHeader!);

    expect(refreshed, isTrue);
    expect(repository.issueCount, 0);
    expect(repository.refreshCount, 1);
    expect(repository.refreshedTokens, ['stale-refresh-token']);
    expect(
      credentialStore.credentials?.authorizationHeader,
      'Bearer fresh-access-token',
    );
  });

  test('익명 인증 세션은 동시 인증 무효화 후 하나의 새 인증 정보를 공유한다', () async {
    final credentialStore = MemoryAnonymousAuthCredentialStore(
      const AnonymousAuthCredentials(
        userId: 'stale-anonymous-user',
        accessToken: 'stale-access-token',
        refreshToken: 'stale-refresh-token',
      ),
    );
    final repository = ControlledAnonymousAuthRepository();
    final session = AnonymousAuthSession(
      repository: repository,
      credentialStore: credentialStore,
    );

    final staleHeader = await session.authorizationHeader();
    final firstRefresh = _invalidateAndReadHeader(session);
    await repository.issueStarted.future;
    final secondRefresh = _invalidateAndReadHeader(session);

    repository.completeIssue(
      const AnonymousAuthCredentials(
        userId: 'fresh-anonymous-user',
        accessToken: 'fresh-access-token',
        refreshToken: 'fresh-refresh-token',
      ),
    );
    final refreshedHeaders = await Future.wait([firstRefresh, secondRefresh]);

    expect(staleHeader, 'Bearer stale-access-token');
    expect(repository.refreshCount, 1);
    expect(repository.refreshedTokens, ['stale-refresh-token']);
    expect(refreshedHeaders.toSet(), hasLength(1));
    expect(refreshedHeaders.toSet().single, 'Bearer fresh-access-token');
    expect(credentialStore.saveCount, 1);
    expect(credentialStore.credentials?.userId, 'fresh-anonymous-user');
  });

  test('익명 인증 세션은 원격 HTTP 주소에서 저장된 인증 정보를 재사용하지 않는다', () async {
    final credentialStore = MemoryAnonymousAuthCredentialStore(
      const AnonymousAuthCredentials(
        userId: 'stored-anonymous-user',
        accessToken: 'stored-access-token',
        refreshToken: 'stored-refresh-token',
      ),
    );
    final httpClient = NetworkFailingHttpClient();
    final session = AnonymousAuthSession(
      repository: AnonymousAuthApiRepository(
        baseUri: Uri.parse('http://example.com'),
        httpClient: httpClient,
      ),
      credentialStore: credentialStore,
    );

    await expectLater(
      session.authorizationHeader(),
      throwsA(isA<AnonymousAuthException>()),
    );
    expect(credentialStore.clearCount, 1);
    expect(credentialStore.credentials, isNull);
    expect(httpClient.postUrlCalled, isFalse);
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

      await expectLater(
        repository.issueAnonymousUser(),
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

    await expectLater(
      repository.issueAnonymousUser(),
      throwsA(isA<AnonymousAuthException>()),
    );
    expect(httpClient.postUrlCalled, isFalse);
  });
}

Future<String?> _invalidateAndReadHeader(AnonymousAuthSession session) async {
  await session.invalidateAuthorization();
  return session.authorizationHeader();
}

class FakeAnonymousAuthRepository implements AnonymousAuthRepository {
  FakeAnonymousAuthRepository({
    this.issueDelay = const Duration(milliseconds: 10),
    this.userId = 'anonymous-user-1',
    this.accessToken = 'access-token-1',
    this.refreshToken = 'refresh-token-1',
  });

  final Duration issueDelay;
  final String userId;
  final String accessToken;
  final String refreshToken;
  int issueCount = 0;
  int refreshCount = 0;
  final refreshedTokens = <String>[];

  @override
  bool get canReuseStoredCredentials => true;

  @override
  Future<AnonymousAuthCredentials> issueAnonymousUser() async {
    issueCount++;
    await Future<void>.delayed(issueDelay);
    return AnonymousAuthCredentials(
      userId: userId,
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  @override
  Future<AnonymousAuthCredentials> refreshAnonymousUser(
    String refreshToken,
  ) async {
    refreshCount++;
    refreshedTokens.add(refreshToken);
    await Future<void>.delayed(issueDelay);
    return AnonymousAuthCredentials(
      userId: userId,
      accessToken: accessToken,
      refreshToken: this.refreshToken,
    );
  }
}

class ControlledAnonymousAuthRepository implements AnonymousAuthRepository {
  final issueStarted = Completer<void>();
  final _issueCompleter = Completer<AnonymousAuthCredentials>();
  final _refreshCompleter = Completer<AnonymousAuthCredentials>();
  var issueCount = 0;
  var refreshCount = 0;
  final refreshedTokens = <String>[];

  @override
  bool get canReuseStoredCredentials => true;

  @override
  Future<AnonymousAuthCredentials> issueAnonymousUser() {
    issueCount++;
    if (!issueStarted.isCompleted) {
      issueStarted.complete();
    }
    return _issueCompleter.future;
  }

  @override
  Future<AnonymousAuthCredentials> refreshAnonymousUser(String refreshToken) {
    refreshCount++;
    refreshedTokens.add(refreshToken);
    if (!issueStarted.isCompleted) {
      issueStarted.complete();
    }
    return _refreshCompleter.future;
  }

  void completeIssue(AnonymousAuthCredentials credentials) {
    if (!_issueCompleter.isCompleted) {
      _issueCompleter.complete(credentials);
    }
    if (!_refreshCompleter.isCompleted) {
      _refreshCompleter.complete(credentials);
    }
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
