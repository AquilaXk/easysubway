import 'dart:async';
import 'dart:io';

import 'data_pack_client.dart';
import 'data_pack_installer.dart';
import 'emergency_override_repository.dart';

const _dataPackDownloadTimeout = Duration(seconds: 20);

class DataPackUpdater {
  DataPackUpdater({
    required this.client,
    required this.installer,
    this.emergencyOverrideRepository,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final DataPackClient client;
  final DataPackInstaller installer;
  final EmergencyOverrideRepository? emergencyOverrideRepository;
  final HttpClient _httpClient;

  Future<List<DataPackInstallResult>> checkForUpdates() async {
    final manifestResult = await client.fetchManifestIfNeeded();
    final manifest = manifestResult.manifest;
    if (manifest == null) {
      return const [];
    }

    final override = manifest.emergencyOverride;
    final protectedVersions = <String>{};
    if (override != null) {
      protectedVersions.add(override.version);
    }

    final packBaseUri = _packBaseUriForManifest(client.manifestUri);
    final results = <DataPackInstallResult>[];
    for (final pack in manifest.packs) {
      final uri = packBaseUri.resolve(pack.url.toString());
      final compressedBytes = await _download(uri);
      results.add(
        await installer.install(
          pack: pack,
          compressedBytes: compressedBytes,
          protectedVersions: protectedVersions,
          activateCurrent: false,
        ),
      );
    }
    if (results.every(
      (result) => result.status == DataPackInstallStatus.installed,
    )) {
      final currentPointer = results.lastOrNull?.pointer;
      if (currentPointer != null) {
        await installer.activateCurrentPointer(currentPointer);
      }
      for (final packId in manifest.packs.map((pack) => pack.id).toSet()) {
        await installer.pruneObsoletePacks(
          packId,
          keepVersionCount: 2,
          protectedVersions: protectedVersions,
        );
      }
      if (override != null) {
        await emergencyOverrideRepository?.saveOverride(
          EmergencyDataPackOverride(
            id: override.id,
            version: override.version,
            reason: override.reason,
          ),
        );
      } else {
        await emergencyOverrideRepository?.clearOverride();
      }
      await client.saveManifestCache(manifestResult);
    }
    return results;
  }

  Uri _packBaseUriForManifest(Uri manifestUri) {
    final manifestDirectory = manifestUri.resolve('./');
    final pathSegments = manifestUri.pathSegments;
    if (pathSegments.length >= 2 &&
        pathSegments[pathSegments.length - 2] == 'catalog' &&
        pathSegments.last == 'current.json') {
      return manifestDirectory.resolve('../');
    }
    return manifestDirectory;
  }

  Future<List<int>> _download(Uri uri) async {
    final request = await _httpClient
        .getUrl(uri)
        .timeout(_dataPackDownloadTimeout);
    final response = await request.close().timeout(_dataPackDownloadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw const DataPackClientException('데이터팩을 내려받지 못했습니다.');
    }
    final bytes = <int>[];
    await for (final chunk in response.timeout(_dataPackDownloadTimeout)) {
      bytes.addAll(chunk);
    }
    return bytes;
  }
}
