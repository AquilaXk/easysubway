import 'dart:async';
import 'dart:io';

import 'data_pack_client.dart';
import 'data_pack_installer.dart';
import 'data_pack_manifest.dart';
import 'emergency_override_repository.dart';

const _dataPackDownloadTimeout = Duration(seconds: 20);
const _maxDataPackDownloadBytes = 250 * 1024 * 1024;

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
    await installer.recoverInstallJournal();
    final packs = _packsToInstall(manifest);
    final results = <DataPackInstallResult>[];
    for (final pack in packs) {
      final uri = packBaseUri.resolve(pack.url.toString());
      final compressedFile = await _downloadToTemporaryFile(uri, pack);
      results.add(
        await installer.installFromCompressedFile(
          pack: pack,
          compressedFile: compressedFile,
          protectedVersions: protectedVersions,
          activateCurrent: false,
        ),
      );
    }
    if (results.every(
      (result) => result.status == DataPackInstallStatus.installed,
    )) {
      final currentPointer = await _currentPointerForManifest(
        manifest: manifest,
        results: results,
      );
      if (currentPointer != null) {
        await installer.activateCurrentPointer(currentPointer);
        protectedVersions.add(_normalizedVersion(currentPointer.version));
      }
      for (final packId in packs.map((pack) => pack.id).toSet()) {
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

  List<DataPackManifestEntry> _packsToInstall(DataPackManifest manifest) {
    final activePack = manifest.activePack;
    if (activePack != null) {
      final activeDependencies = manifest.packs
          .where(
            (pack) =>
                pack.id == activePack.id &&
                _versionNumber(pack.version) ==
                    _versionNumber(activePack.version),
          )
          .expand((pack) => pack.dependencies)
          .toList(growable: false);
      return manifest.packs
          .where(
            (pack) =>
                pack.id == activePack.id ||
                activeDependencies.any(
                  (dependency) =>
                      dependency.id == pack.id &&
                      _versionNumber(dependency.version) ==
                          _versionNumber(pack.version),
                ),
          )
          .toList(growable: false);
    }
    return manifest.packs
        .where((pack) => pack.id == activePackId)
        .toList(growable: false);
  }

  Future<InstalledDataPackPointer?> _currentPointerForManifest({
    required DataPackManifest manifest,
    required List<DataPackInstallResult> results,
  }) async {
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
      final installedPointer = await installer.readInstalledPointer(
        id: activePack.id,
        version: activePack.version,
      );
      if (installedPointer != null) {
        return installedPointer;
      }
      throw const DataPackClientException('활성 데이터팩을 선택하지 못했습니다.');
    }

    if (results.isEmpty) {
      return null;
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

  Future<File> _downloadToTemporaryFile(
    Uri uri,
    DataPackManifestEntry pack,
  ) async {
    final request = await _httpClient
        .getUrl(uri)
        .timeout(_dataPackDownloadTimeout);
    final response = await request.close().timeout(_dataPackDownloadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw const DataPackClientException('데이터팩을 내려받지 못했습니다.');
    }
    final expectedSizeBytes = pack.sizeBytes;
    final contentLength = response.contentLength;
    final maxBytes = expectedSizeBytes ?? _maxDataPackDownloadBytes;
    if (contentLength > maxBytes || contentLength > _maxDataPackDownloadBytes) {
      throw const DataPackClientException('데이터팩 크기가 허용 범위를 넘었습니다.');
    }
    final directory = await installer.catalogDirectory.create(recursive: true);
    final temporary = File(
      '${directory.path}/${pack.id}-v${pack.version}.sqlite.gz.downloading',
    );
    final sink = temporary.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.timeout(_dataPackDownloadTimeout)) {
        received += chunk.length;
        if (received > maxBytes || received > _maxDataPackDownloadBytes) {
          throw const DataPackClientException('데이터팩 크기가 허용 범위를 넘었습니다.');
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      return temporary;
    } on Object {
      await sink.close();
      await _deleteIfExists(temporary);
      rethrow;
    }
  }
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

int _versionNumber(String version) {
  return int.tryParse(version) ?? 0;
}

String _normalizedVersion(String version) {
  return _versionNumber(version).toString();
}
