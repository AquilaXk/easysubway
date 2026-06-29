import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_error.dart';

export 'api_error.dart';

const defaultApiTimeout = Duration(seconds: 8);

class ApiClient {
  ApiClient({
    required this.baseUri,
    HttpClient? httpClient,
    this.timeout = defaultApiTimeout,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final Duration timeout;
  final HttpClient _httpClient;

  Future<ApiResponse> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) {
    return _requestJson(HttpMethod.get, path, headers: headers);
  }

  Future<ApiResponse> deleteJson(
    String path, {
    Map<String, String> headers = const {},
  }) {
    return _requestJson(HttpMethod.delete, path, headers: headers);
  }

  Future<ApiResponse> postJson(
    String path, {
    required Map<String, Object?> body,
    Map<String, String> headers = const {},
  }) {
    return _requestJson(
      HttpMethod.post,
      path,
      headers: headers,
      requestBody: body,
    );
  }

  Future<ApiResponse> putJson(
    String path, {
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) {
    return _requestJson(
      HttpMethod.put,
      path,
      headers: headers,
      requestBody: body,
    );
  }

  Future<ApiResponse> putBytes(
    Uri uri, {
    required List<int> body,
    required ContentType contentType,
    Map<String, String> headers = const {},
  }) async {
    try {
      final request = await _httpClient.putUrl(uri).timeout(timeout);
      headers.forEach(request.headers.set);
      request.headers.contentType = contentType;
      request.contentLength = body.length;
      request.add(body);

      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      return ApiResponse(statusCode: response.statusCode, jsonBody: null);
    } on TimeoutException catch (error, stackTrace) {
      throw ApiException(
        '연결 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      throw ApiException(
        '서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      throw ApiException(
        '요청을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<ApiResponse> _requestJson(
    HttpMethod method,
    String path, {
    required Map<String, String> headers,
    Map<String, Object?>? requestBody,
  }) async {
    final uri = baseUri.resolve(path);
    try {
      final request = await _open(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
      headers.forEach(request.headers.set);
      if (requestBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(requestBody));
      }

      final response = await request.close().timeout(timeout);
      final responseBody = await utf8.decodeStream(response).timeout(timeout);
      if (!_isSuccessStatus(response.statusCode)) {
        return ApiResponse(statusCode: response.statusCode, jsonBody: null);
      }
      final decoded = _decodeJson(
        responseBody,
        statusCode: response.statusCode,
        uri: uri,
      );
      return ApiResponse(statusCode: response.statusCode, jsonBody: decoded);
    } on ApiException {
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      throw ApiException(
        '연결 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      throw ApiException(
        '서버에 연결하지 못했어요. 인터넷 연결을 확인해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      throw ApiException(
        '요청을 완료하지 못했어요. 잠시 후 다시 시도해 주세요.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
  }

  Future<HttpClientRequest> _open(HttpMethod method, Uri uri) {
    switch (method) {
      case HttpMethod.get:
        return _httpClient.getUrl(uri);
      case HttpMethod.delete:
        return _httpClient.deleteUrl(uri);
      case HttpMethod.post:
        return _httpClient.postUrl(uri);
      case HttpMethod.put:
        return _httpClient.putUrl(uri);
    }
  }
}

class ApiResponse {
  const ApiResponse({required this.statusCode, required this.jsonBody});

  final int statusCode;
  final Object? jsonBody;

  bool get isUnauthorized => statusCode == HttpStatus.unauthorized;
  bool get isOk => statusCode == HttpStatus.ok;
  bool get isSuccess => _isSuccessStatus(statusCode);

  Object? requireSuccessData({
    required Object Function() errorFactory,
    int? expectedStatusCode,
  }) {
    final statusMatches = expectedStatusCode == null
        ? isSuccess
        : statusCode == expectedStatusCode;
    if (!statusMatches) {
      throw errorFactory();
    }

    final decoded = jsonBody;
    if (decoded is! Map<String, Object?> || decoded['success'] != true) {
      throw errorFactory();
    }
    return decoded['data'];
  }
}

enum HttpMethod { get, delete, post, put }

Object? _decodeJson(String body, {required int statusCode, required Uri uri}) {
  try {
    return jsonDecode(body);
  } on FormatException catch (error, stackTrace) {
    throw ApiException(
      '받은 정보를 읽지 못했어요. 잠시 후 다시 시도해 주세요.',
      statusCode: statusCode,
      path: uri.path,
      cause: error,
      causeStackTrace: stackTrace,
    );
  }
}

bool _isSuccessStatus(int statusCode) {
  return statusCode >= HttpStatus.ok && statusCode < HttpStatus.multipleChoices;
}
