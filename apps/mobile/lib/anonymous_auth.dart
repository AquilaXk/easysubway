import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'station_search.dart';

const _anonymousAuthTimeout = Duration(seconds: 8);
const _anonymousAuthErrorMessage = '인증을 준비하지 못했습니다. 잠시 후 다시 시도해 주세요.';

abstract class AnonymousAuthRepository {
  Future<AnonymousAuthCredentials> issueAnonymousUser();
}

class AnonymousAuthApiRepository implements AnonymousAuthRepository {
  AnonymousAuthApiRepository({required this.baseUri, HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _httpClient;

  @override
  Future<AnonymousAuthCredentials> issueAnonymousUser() async {
    final uri = baseUri.resolve('/api/v1/auth/anonymous');

    try {
      if (!_isAllowedAnonymousAuthBaseUri(uri)) {
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
  AnonymousAuthSession({required this.repository});

  final AnonymousAuthRepository repository;
  AnonymousAuthCredentials? _credentials;
  Future<AnonymousAuthCredentials>? _issuingCredentials;

  @override
  Future<String?> authorizationHeader() async {
    final credentials = await _currentCredentials();
    return credentials.authorizationHeader;
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

    // 여러 API가 동시에 인증을 요구해도 익명 계정은 한 번만 발급한다.
    final nextIssuingCredentials = repository.issueAnonymousUser();
    _issuingCredentials = nextIssuingCredentials;
    try {
      final issuedCredentials = await nextIssuingCredentials;
      _credentials = issuedCredentials;
      return issuedCredentials;
    } finally {
      if (identical(_issuingCredentials, nextIssuingCredentials)) {
        _issuingCredentials = null;
      }
    }
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

bool _isAllowedAnonymousAuthBaseUri(Uri uri) {
  if (uri.scheme == 'https') {
    return true;
  }

  // Basic 인증은 개발용 로컬 주소 외에는 평문 HTTP로 보내지 않는다.
  if (uri.scheme != 'http') {
    return false;
  }

  final host = uri.host.toLowerCase();
  return host == 'localhost' ||
      host == '::1' ||
      host == '10.0.2.2' ||
      _isIpv4LoopbackLiteral(host);
}

bool _isIpv4LoopbackLiteral(String host) {
  final address = InternetAddress.tryParse(host);
  return address != null &&
      address.type == InternetAddressType.IPv4 &&
      address.rawAddress.first == 127;
}
