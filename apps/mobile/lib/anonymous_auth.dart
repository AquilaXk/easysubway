import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'auth_headers.dart';
import 'mobile_error_reporter.dart';
import 'secure_key_value_storage.dart';

const _anonymousAuthTimeout = Duration(seconds: 8);
const _anonymousAuthErrorMessage = '인증을 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.';
const _anonymousAuthCredentialsKey = 'easysubway.anonymousAuth.credentials';

abstract class AnonymousAuthRepository {
  Future<AnonymousAuthCredentials> issueAnonymousUser();

  Future<AnonymousAuthCredentials> refreshAnonymousUser(String refreshToken);

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
    this.storage = const FlutterSecureKeyValueStorage(),
  });

  final SecureKeyValueStorage storage;

  @override
  Future<AnonymousAuthCredentials?> readCredentials() async {
    try {
      final value = await storage.read(key: _anonymousAuthCredentialsKey);
      if (value == null) {
        return null;
      }
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Invalid anonymous auth storage payload');
      }
      return AnonymousAuthCredentials.fromJson(decoded);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '저장된 익명 인증 정보를 읽는 중 예외가 발생했습니다.',
      );
      await _clearCredentialsAfterReadFailure();
      return null;
    }
  }

  @override
  Future<void> saveCredentials(AnonymousAuthCredentials credentials) async {
    await storage.write(
      key: _anonymousAuthCredentialsKey,
      value: jsonEncode({
        'userId': credentials.userId,
        'accessToken': credentials.accessToken,
        'refreshToken': credentials.refreshToken,
      }),
    );
  }

  @override
  Future<void> clearCredentials() async {
    await storage.delete(key: _anonymousAuthCredentialsKey);
  }

  Future<void> _clearCredentialsAfterReadFailure() async {
    try {
      await clearCredentials();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '손상된 익명 인증 정보를 지우는 중 예외가 발생했습니다.',
      );
    }
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
    return _postCredentials(baseUri.resolve('/api/v1/auth/anonymous'));
  }

  @override
  Future<AnonymousAuthCredentials> refreshAnonymousUser(
    String refreshToken,
  ) async {
    return _postCredentials(
      baseUri.resolve('/api/v1/auth/anonymous/refresh'),
      requestBody: jsonEncode({'refreshToken': refreshToken}),
    );
  }

  Future<AnonymousAuthCredentials> _postCredentials(
    Uri uri, {
    String? requestBody,
  }) async {
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
      if (requestBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(requestBody);
      }
      final response = await request.close().timeout(_anonymousAuthTimeout);
      final responseBody = await utf8
          .decodeStream(response)
          .timeout(_anonymousAuthTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw const AnonymousAuthException(_anonymousAuthErrorMessage);
      }

      final decoded = jsonDecode(responseBody);
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
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '익명 인증 API 응답 처리 중 예외가 발생했습니다.',
      );
      throw const AnonymousAuthException(_anonymousAuthErrorMessage);
    }
  }
}

class AnonymousAuthSession implements AuthorizationHeaderProvider {
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
    final issuingCredentials = _issuingCredentials;
    if (issuingCredentials != null) {
      await issuingCredentials;
      return;
    }

    final credentials = _credentials ?? await credentialStore.readCredentials();
    _credentials = null;
    if (credentials == null) {
      await credentialStore.clearCredentials();
      return;
    }

    final nextIssuingCredentials = _refreshOrIssueCredentials(credentials);
    _issuingCredentials = nextIssuingCredentials;
    try {
      await nextIssuingCredentials;
    } finally {
      if (identical(_issuingCredentials, nextIssuingCredentials)) {
        _issuingCredentials = null;
      }
    }
  }

  Future<AnonymousAuthCredentials> _refreshOrIssueCredentials(
    AnonymousAuthCredentials credentials,
  ) async {
    try {
      final refreshedCredentials = await repository.refreshAnonymousUser(
        credentials.refreshToken,
      );
      return await _saveCurrentCredentials(refreshedCredentials);
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '익명 인증 refresh token 갱신 중 예외가 발생했습니다.',
      );
      await credentialStore.clearCredentials();
      final issuedCredentials = await repository.issueAnonymousUser();
      return _saveCurrentCredentials(issuedCredentials);
    }
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
    return _saveCurrentCredentials(issuedCredentials);
  }

  Future<AnonymousAuthCredentials> _saveCurrentCredentials(
    AnonymousAuthCredentials credentials,
  ) async {
    await credentialStore.saveCredentials(credentials);
    _credentials = credentials;
    return credentials;
  }
}

class AnonymousAuthCredentials {
  const AnonymousAuthCredentials({
    required this.userId,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AnonymousAuthCredentials.fromJson(Map<String, Object?> json) {
    return AnonymousAuthCredentials(
      userId: _requiredAuthString(json, 'userId'),
      accessToken: _requiredAuthString(json, 'accessToken'),
      refreshToken: _requiredAuthString(json, 'refreshToken'),
    );
  }

  final String userId;
  final String accessToken;
  final String refreshToken;

  String get authorizationHeader => 'Bearer $accessToken';
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

  // 인증 token은 개발용 로컬 주소와 debug 에뮬레이터 별칭 외에는 평문 HTTP로 보내지 않는다.
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
