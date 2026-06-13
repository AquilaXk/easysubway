import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'station_search.dart';

const _anonymousAuthTimeout = Duration(seconds: 8);
const _anonymousAuthErrorMessage = '인증을 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.';
const _anonymousAuthCredentialsKey = 'easysubway.anonymousAuth.credentials';

abstract class AnonymousAuthRepository {
  Future<AnonymousAuthCredentials> issueAnonymousUser();

  bool get canReuseStoredCredentials => true;
}

abstract class AnonymousAuthCredentialStore {
  Future<AnonymousAuthCredentials?> readCredentials();

  Future<void> saveCredentials(AnonymousAuthCredentials credentials);

  Future<void> clearCredentials();
}

class SecureAnonymousAuthCredentialStore
    implements AnonymousAuthCredentialStore {
  const SecureAnonymousAuthCredentialStore({
    this.storage = const FlutterSecureStorage(),
  });

  final FlutterSecureStorage storage;

  @override
  Future<AnonymousAuthCredentials?> readCredentials() async {
    final value = await storage.read(key: _anonymousAuthCredentialsKey);
    if (value == null) {
      return null;
    }

    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Invalid anonymous auth storage payload');
      }
      return AnonymousAuthCredentials.fromJson(decoded);
    } catch (_) {
      await clearCredentials();
      return null;
    }
  }

  @override
  Future<void> saveCredentials(AnonymousAuthCredentials credentials) async {
    await storage.write(
      key: _anonymousAuthCredentialsKey,
      value: jsonEncode({
        'userId': credentials.userId,
        'password': credentials.password,
      }),
    );
  }

  @override
  Future<void> clearCredentials() async {
    await storage.delete(key: _anonymousAuthCredentialsKey);
  }
}

class AnonymousAuthApiRepository implements AnonymousAuthRepository {
  AnonymousAuthApiRepository({
    required this.baseUri,
    HttpClient? httpClient,
    this.allowAndroidEmulatorHttp = kDebugMode,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _httpClient;
  final bool allowAndroidEmulatorHttp;

  @override
  bool get canReuseStoredCredentials {
    return _isAllowedAnonymousAuthBaseUri(
      baseUri.resolve('/api/v1/auth/anonymous'),
      allowAndroidEmulatorHttp: allowAndroidEmulatorHttp,
    );
  }

  @override
  Future<AnonymousAuthCredentials> issueAnonymousUser() async {
    final uri = baseUri.resolve('/api/v1/auth/anonymous');

    try {
      if (!_isAllowedAnonymousAuthBaseUri(
        uri,
        allowAndroidEmulatorHttp: allowAndroidEmulatorHttp,
      )) {
        throw const AnonymousAuthException(_anonymousAuthErrorMessage);
      }

      final request = await _httpClient
          .postUrl(uri)
          .timeout(_anonymousAuthTimeout);
      final response = await request.close().timeout(_anonymousAuthTimeout);
      final body = await utf8
          .decodeStream(response)
          .timeout(_anonymousAuthTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw const AnonymousAuthException(_anonymousAuthErrorMessage);
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const AnonymousAuthException(_anonymousAuthErrorMessage);
      }

      final data = decoded['data'];
      if (data is! Map<String, Object?>) {
        throw const AnonymousAuthException(_anonymousAuthErrorMessage);
      }

      return AnonymousAuthCredentials.fromJson(data);
    } on AnonymousAuthException {
      rethrow;
    } catch (_) {
      throw const AnonymousAuthException(_anonymousAuthErrorMessage);
    }
  }
}

class AnonymousAuthSession implements FavoriteStationAuthProvider {
  AnonymousAuthSession({
    required this.repository,
    AnonymousAuthCredentialStore? credentialStore,
  }) : credentialStore =
           credentialStore ?? const SecureAnonymousAuthCredentialStore();

  final AnonymousAuthRepository repository;
  final AnonymousAuthCredentialStore credentialStore;
  AnonymousAuthCredentials? _credentials;
  Future<AnonymousAuthCredentials>? _issuingCredentials;

  @override
  Future<String?> authorizationHeader() async {
    final credentials = await _currentCredentials();
    return credentials.authorizationHeader;
  }

  @override
  Future<void> invalidateAuthorization() async {
    _credentials = null;
    _issuingCredentials = null;
    await credentialStore.clearCredentials();
  }

  Future<AnonymousAuthCredentials> _currentCredentials() async {
    final cachedCredentials = _credentials;
    if (cachedCredentials != null) {
      return cachedCredentials;
    }

    final issuingCredentials = _issuingCredentials;
    if (issuingCredentials != null) {
      return issuingCredentials;
    }

    // 저장소 조회와 신규 발급을 하나로 묶어 동시 호출에서도 익명 계정을 한 번만 준비한다.
    final nextIssuingCredentials = _loadOrIssueCredentials();
    _issuingCredentials = nextIssuingCredentials;
    try {
      return await nextIssuingCredentials;
    } finally {
      if (identical(_issuingCredentials, nextIssuingCredentials)) {
        _issuingCredentials = null;
      }
    }
  }

  Future<AnonymousAuthCredentials> _loadOrIssueCredentials() async {
    final storedCredentials = await credentialStore.readCredentials();
    if (storedCredentials != null) {
      if (!repository.canReuseStoredCredentials) {
        await credentialStore.clearCredentials();
        throw const AnonymousAuthException(_anonymousAuthErrorMessage);
      }
      _credentials = storedCredentials;
      return storedCredentials;
    }

    final issuedCredentials = await repository.issueAnonymousUser();
    await credentialStore.saveCredentials(issuedCredentials);
    _credentials = issuedCredentials;
    return issuedCredentials;
  }
}

class AnonymousAuthCredentials {
  const AnonymousAuthCredentials({
    required this.userId,
    required this.password,
  });

  factory AnonymousAuthCredentials.fromJson(Map<String, Object?> json) {
    return AnonymousAuthCredentials(
      userId: _requiredAuthString(json, 'userId'),
      password: _requiredAuthString(json, 'password'),
    );
  }

  final String userId;
  final String password;

  String get authorizationHeader {
    final token = base64Encode(utf8.encode('$userId:$password'));
    return 'Basic $token';
  }
}

class AnonymousAuthException implements Exception {
  const AnonymousAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _requiredAuthString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid anonymous auth payload');
  }
  return value.trim();
}

bool _isAllowedAnonymousAuthBaseUri(
  Uri uri, {
  required bool allowAndroidEmulatorHttp,
}) {
  if (uri.scheme == 'https') {
    return true;
  }

  // Basic 인증은 개발용 로컬 주소와 debug 에뮬레이터 별칭 외에는 평문 HTTP로 보내지 않는다.
  if (uri.scheme != 'http') {
    return false;
  }

  final host = uri.host.toLowerCase();
  return host == 'localhost' ||
      host == '::1' ||
      (allowAndroidEmulatorHttp && host == '10.0.2.2') ||
      _isIpv4LoopbackLiteral(host);
}

bool _isIpv4LoopbackLiteral(String host) {
  final address = InternetAddress.tryParse(host);
  return address != null &&
      address.type == InternetAddressType.IPv4 &&
      address.rawAddress.first == 127;
}
