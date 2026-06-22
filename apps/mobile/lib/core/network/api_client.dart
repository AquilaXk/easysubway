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
        'API 요청 시간이 초과되었습니다.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      throw ApiException(
        'API 서버에 연결하지 못했습니다.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      throw ApiException(
        'API 요청을 처리하지 못했습니다.',
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
        'API 요청 시간이 초과되었습니다.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      throw ApiException(
        'API 서버에 연결하지 못했습니다.',
        path: uri.path,
        cause: error,
        causeStackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      throw ApiException(
        'API 요청을 처리하지 못했습니다.',
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
}

enum HttpMethod { get, delete, post }

Object? _decodeJson(String body, {required int statusCode, required Uri uri}) {
  try {
    return jsonDecode(body);
  } on FormatException catch (error, stackTrace) {
    throw ApiException(
      'API JSON 응답을 해석하지 못했습니다.',
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
