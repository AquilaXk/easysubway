import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'data_pack_manifest.dart';
import 'data_pack_update_state.dart';

const _manifestFetchTimeout = Duration(seconds: 8);

class DataPackClient {
  DataPackClient({
    required this.manifestUri,
    required this.stateRepository,
    this.productionSigningPublicKey,
    this.expectedManifestChannel = 'production',
    HttpClient? httpClient,
    DateTime Function()? now,
  }) : _httpClient = httpClient ?? HttpClient(),
       _now = now ?? DateTime.now;

  final Uri manifestUri;
  final DataPackUpdateStateRepository stateRepository;
  final DataPackSigningPublicKey? productionSigningPublicKey;
  final String expectedManifestChannel;
  final HttpClient _httpClient;
  final DateTime Function() _now;

  Future<DataPackManifestFetchResult> fetchManifestIfNeeded() async {
    final cache = await stateRepository.readManifestCache();
    if (cache != null && stateRepository.isFresh(cache)) {
      return const DataPackManifestFetchResult(
        status: DataPackManifestFetchStatus.freshCache,
      );
    }

    final request = await _httpClient
        .getUrl(manifestUri)
        .timeout(_manifestFetchTimeout);
    final etag = cache?.etag;
    if (etag != null && etag.isNotEmpty) {
      request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
    }

    final response = await request.close().timeout(_manifestFetchTimeout);
    if (response.statusCode == HttpStatus.notModified && cache != null) {
      final checkedAt = _now().toUtc();
      await stateRepository.saveManifestCache(
        etag: cache.etag,
        checkedAt: checkedAt,
        ttl: _cacheTtlBoundedByExpiry(cache.ttl, cache.expiresAt, checkedAt),
        expiresAt: cache.expiresAt,
      );
      return const DataPackManifestFetchResult(
        status: DataPackManifestFetchStatus.notModified,
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw const DataPackClientException('데이터팩 정보를 확인하지 못했습니다.');
    }

    final body = await utf8
        .decodeStream(response)
        .timeout(_manifestFetchTimeout);
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const DataPackClientException('데이터팩 정보 형식이 올바르지 않습니다.');
    }
    if (decoded is! Map<String, Object?>) {
      throw const DataPackClientException('데이터팩 정보 형식이 올바르지 않습니다.');
    }
    final DataPackManifest manifest;
    try {
      manifest = DataPackManifest.fromJson(
        decoded,
        productionSigningPublicKey: productionSigningPublicKey,
      );
    } on FormatException {
      throw const DataPackClientException('데이터팩 정보 형식이 올바르지 않습니다.');
    }
    _ensureExpectedManifestChannel(manifest);
    if (manifest.isExpiredAt(_now())) {
      throw const DataPackClientException('데이터팩 정보가 만료되었습니다.');
    }
    try {
      await stateRepository.ensureManifestCanBeAccepted(manifest);
    } on DataPackManifestReplayException catch (error) {
      throw DataPackClientException(error.message);
    }
    return DataPackManifestFetchResult(
      status: DataPackManifestFetchStatus.updated,
      manifest: manifest,
      etag: response.headers.value(HttpHeaders.etagHeader),
      checkedAt: _now().toUtc(),
    );
  }

  Future<void> saveManifestCache(DataPackManifestFetchResult result) async {
    final manifest = result.manifest;
    final checkedAt = result.checkedAt;
    if (manifest == null || checkedAt == null) {
      return;
    }
    _ensureExpectedManifestChannel(manifest);
    final expiresAt = manifest.expiresAt;
    await stateRepository.saveAcceptedManifestState(manifest);
    await stateRepository.saveManifestCache(
      etag: result.etag,
      checkedAt: checkedAt,
      ttl: _cacheTtlBoundedByExpiry(manifest.ttl, expiresAt, checkedAt),
      expiresAt: expiresAt,
    );
  }

  Duration _cacheTtlBoundedByExpiry(
    Duration ttl,
    DateTime? expiresAt,
    DateTime checkedAt,
  ) {
    if (expiresAt == null) {
      return ttl;
    }
    final expiryTtl = expiresAt.difference(checkedAt.toUtc());
    if (expiryTtl <= Duration.zero) {
      throw const DataPackClientException('데이터팩 정보가 만료되었습니다.');
    }
    return expiryTtl < ttl ? expiryTtl : ttl;
  }

  void _ensureExpectedManifestChannel(DataPackManifest manifest) {
    if (!manifest.hasReplayProtection) {
      return;
    }
    final expected = expectedManifestChannel.trim().isEmpty
        ? 'production'
        : expectedManifestChannel.trim();
    if (manifest.channel != expected) {
      throw const DataPackClientException('데이터팩 manifest 채널이 올바르지 않습니다.');
    }
  }
}

class DataPackManifestFetchResult {
  const DataPackManifestFetchResult({
    required this.status,
    this.manifest,
    this.etag,
    this.checkedAt,
  });

  final DataPackManifestFetchStatus status;
  final DataPackManifest? manifest;
  final String? etag;
  final DateTime? checkedAt;
}

enum DataPackManifestFetchStatus { freshCache, notModified, updated }

class DataPackClientException implements Exception {
  const DataPackClientException(this.message);

  final String message;

  @override
  String toString() => message;
}
