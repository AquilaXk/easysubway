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
    HttpClient? httpClient,
    DateTime Function()? now,
  }) : _httpClient = httpClient ?? HttpClient(),
       _now = now ?? DateTime.now;

  final Uri manifestUri;
  final DataPackUpdateStateRepository stateRepository;
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
      await stateRepository.saveManifestCache(
        etag: cache.etag,
        checkedAt: _now().toUtc(),
        ttl: cache.ttl,
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
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw const DataPackClientException('데이터팩 정보 형식이 올바르지 않습니다.');
    }
    final manifest = DataPackManifest.fromJson(decoded);
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
    await stateRepository.saveManifestCache(
      etag: result.etag,
      checkedAt: checkedAt,
      ttl: manifest.ttl,
    );
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
