import 'dart:convert';

abstract class AuthorizationHeaderProvider {
  Future<String?> authorizationHeader();

  Future<void> invalidateAuthorization();
}

class NoAuthorizationHeaderProvider implements AuthorizationHeaderProvider {
  const NoAuthorizationHeaderProvider();

  @override
  Future<String?> authorizationHeader() async => null;

  @override
  Future<void> invalidateAuthorization() async {}
}

class BasicAuthorizationHeaderProvider implements AuthorizationHeaderProvider {
  const BasicAuthorizationHeaderProvider({
    required this.username,
    required this.password,
  });

  final String username;
  final String password;

  @override
  Future<String?> authorizationHeader() async {
    // 개발용 Basic 인증은 값이 주입된 경우에만 만들고, 빈 값은 인증 없이 요청하게 둔다.
    if (username.trim().isEmpty || password.isEmpty) {
      return null;
    }
    final token = base64Encode(utf8.encode('${username.trim()}:$password'));
    return 'Basic $token';
  }

  @override
  Future<void> invalidateAuthorization() async {}
}
