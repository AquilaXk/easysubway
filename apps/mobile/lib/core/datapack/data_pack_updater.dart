import 'dart:async';
import 'dart:io';

import 'data_pack_client.dart';
import 'data_pack_installer.dart';
import 'data_pack_manifest.dart';
import 'emergency_override_repository.dart';

const _dataPackDownloadTimeout = Duration(seconds: 20);

class DataPackUpdater {
  DataPackUpdater({
    required this.client,
    required this.installer,
    this.emergencyOverrideRepository,
    this.activePackId = 'capital',
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final DataPackClient client;
  final DataPackInstaller installer;
  final EmergencyOverrideRepository? emergencyOverrideRepository;
  final String activePackId;
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
      protectedVersions.add(_normalizedVersion(override.version));
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
      final currentPointer = _currentPointerForManifest(
        manifest: manifest,
        results: results,
      );
      if (currentPointer != null) {
        await installer.activateCurrentPointer(currentPointer);
        protectedVersions.add(_normalizedVersion(currentPointer.version));
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

  InstalledDataPackPointer? _currentPointerForManifest({
    required DataPackManifest manifest,
    required List<DataPackInstallResult> results,
  }) {
    if (results.isEmpty) {
      return null;
    }

    final activePack = manifest.activePack;
    if (activePack != null) {
      for (final result in results) {
        final pointer = result.pointer;
        if (pointer?.id == activePack.id &&
            _versionNumber(pointer?.version ?? '') ==
                _versionNumber(activePack.version)) {
          return pointer;
        }
      }
      throw const DataPackClientException('활성 데이터팩을 선택하지 못했습니다.');
    }

    InstalledDataPackPointer? selected;
    for (final result in results) {
      final pointer = result.pointer;
      if (pointer == null || pointer.id != activePackId) {
        continue;
      }
      if (selected == null ||
          _versionNumber(pointer.version) > _versionNumber(selected.version)) {
        selected = pointer;
      }
    }
    if (selected == null) {
      throw const DataPackClientException('활성 데이터팩을 선택하지 못했습니다.');
    }
    return selected;
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

int _versionNumber(String version) {
  return int.tryParse(version) ?? 0;
}

String _normalizedVersion(String version) {
  return _versionNumber(version).toString();
}
