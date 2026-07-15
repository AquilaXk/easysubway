import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'core/network/api_client.dart';
import 'route_search.dart';

abstract interface class PlayIntegrityAttestor {
  Future<String> requestToken(String requestHash);
}

class MethodChannelPlayIntegrityAttestor implements PlayIntegrityAttestor {
  MethodChannelPlayIntegrityAttestor({
    MethodChannel? channel,
    this.cloudProjectNumber = const String.fromEnvironment(
      'EASYSUBWAY_PLAY_INTEGRITY_CLOUD_PROJECT_NUMBER',
    ),
  }) : _channel =
           channel ??
           const MethodChannel(
             'com.easysubway.easysubway_mobile/play_integrity',
           );

  final MethodChannel _channel;
  final String cloudProjectNumber;

  @override
  Future<String> requestToken(String requestHash) async {
    if (cloudProjectNumber.isEmpty) {
      throw StateError('Play Integrity cloud project is not configured.');
    }
    final token = await _channel.invokeMethod<String>('requestToken', {
      'requestHash': requestHash,
      'cloudProjectNumber': cloudProjectNumber,
    });
    if (token == null || token.isEmpty) {
      throw StateError('Play Integrity token is unavailable.');
    }
    return token;
  }
}

class PlayIntegrityRouteV2SessionProvider {
  PlayIntegrityRouteV2SessionProvider({
    required this.apiClient,
    required this.attestor,
    String Function()? nonceFactory,
  }) : _nonceFactory = nonceFactory ?? _secureNonce;

  final ApiClient apiClient;
  final PlayIntegrityAttestor attestor;
  final String Function() _nonceFactory;

  Future<String> issueToken() async {
    final nonce = _nonceFactory();
    final integrityToken = await attestor.requestToken(requestHash(nonce));
    final response = await apiClient.postJson(
      '/api/v2/routes/session',
      body: {'integrityToken': integrityToken, 'clientNonce': nonce},
    );
    if (!response.isSuccess) {
      throw RouteSearchOnlineException.response(response);
    }
    final body = response.jsonBody;
    if (body is! Map<String, Object?>) {
      throw const RouteSearchOnlineException.unavailable(
        failureReason: 'ROUTE_SESSION_ATTESTATION_REJECTED',
      );
    }
    final token = body['token'];
    final scope = body['scope'];
    if (token is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token) ||
        scope != 'route:v2:itx') {
      throw const RouteSearchOnlineException.unavailable(
        failureReason: 'ROUTE_SESSION_ATTESTATION_REJECTED',
      );
    }
    return token;
  }

  static String canonicalRequest(String nonce) =>
      '{"clientNonce":"$nonce","purpose":"route:v2:itx","version":1}';

  static String requestHash(String nonce) => base64Url
      .encode(sha256.convert(utf8.encode(canonicalRequest(nonce))).bytes)
      .replaceAll('=', '');

  static String _secureNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class TransportScopedRouteSearchRepository implements RouteSearchRepository {
  TransportScopedRouteSearchRepository({
    required this.localRepository,
    required this.itxOnlineRepository,
  });

  final RouteSearchRepository localRepository;
  final RouteSearchRepository itxOnlineRepository;
  final Set<String> _onlineRouteIds = {};

  @override
  Future<RouteSearchResult> searchRoute(RouteSearchRequest request) async {
    if (request.transportScope == RouteTransportScope.subway) {
      return localRepository.searchRoute(request);
    }
    final result = await itxOnlineRepository.searchRoute(request);
    _onlineRouteIds.add(result.routeSearchId);
    return result;
  }

  @override
  Future<RouteRefreshResult> refreshRoute(String routeSearchId) {
    return _onlineRouteIds.contains(routeSearchId)
        ? itxOnlineRepository.refreshRoute(routeSearchId)
        : localRepository.refreshRoute(routeSearchId);
  }
}
