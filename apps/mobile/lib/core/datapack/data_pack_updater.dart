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
    await installer.recoverInstallJournal();
    final manifestResult = await client.fetchManifestIfNeeded();
    final manifest = manifestResult.manifest;
    if (manifest == null) {
      return const [];
    }

    final preUpdateCurrentPointer = await _readCurrentPointerSafely();
    final override = manifest.emergencyOverride;
    final protectedVersionsByPackId = <String, Set<String>>{};
    if (preUpdateCurrentPointer != null) {
      _protectVersion(
        protectedVersionsByPackId,
        id: preUpdateCurrentPointer.id,
        version: preUpdateCurrentPointer.version,
      );
    }
    if (override != null) {
      _protectVersion(
        protectedVersionsByPackId,
        id: override.id,
        version: override.version,
      );
    }

    final packBaseUri = _packBaseUriForManifest(client.manifestUri);
    final packs = _packsToInstall(manifest);
    final results = <DataPackInstallResult>[];
    for (final pack in packs) {
      final uri = packBaseUri.resolve(pack.url.toString());
      final compressedFile = await _downloadToTemporaryFile(uri, pack);
      results.add(
        await installer.installFromCompressedFile(
          pack: pack,
          compressedFile: compressedFile,
          protectedVersions:
              protectedVersionsByPackId[pack.id] ?? const <String>{},
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
        _protectVersion(
          protectedVersionsByPackId,
          id: currentPointer.id,
          version: currentPointer.version,
        );
      }
      for (final result in results) {
        final pointer = result.pointer;
        if (pointer != null) {
          _protectVersion(
            protectedVersionsByPackId,
            id: pointer.id,
            version: pointer.version,
          );
        }
      }
      for (final packId in packs.map((pack) => pack.id).toSet()) {
        await installer.pruneObsoletePacks(
          packId,
          keepVersionCount: 2,
          protectedVersions:
              protectedVersionsByPackId[packId] ?? const <String>{},
        );
      }
      if (override != null) {
        final installedOverride = await installer.readInstalledPointer(
          id: override.id,
          version: override.version,
        );
        if (installedOverride != null) {
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
      } else {
        await emergencyOverrideRepository?.clearOverride();
      }
      await client.saveManifestCache(manifestResult);
    }
    return results;
  }

  Future<InstalledDataPackPointer?> _readCurrentPointerSafely() async {
    try {
      return await installer.readCurrentPointer();
    } on Object {
      return null;
    }
  }

  List<DataPackManifestEntry> _packsToInstall(DataPackManifest manifest) {
    final activePack = manifest.activePack;
    final override = manifest.emergencyOverride;
    final selectedPacks = manifest.packs
        .where((pack) {
          final selectedActiveId = activePack?.id ?? activePackId;
          return pack.id == selectedActiveId ||
              _matchesOverride(pack, override);
        })
        .toList(growable: false);
    final selectedDependencies = selectedPacks
        .expand((pack) => pack.dependencies)
        .toList(growable: false);
    return manifest.packs
        .where((pack) {
          if (selectedPacks.contains(pack)) {
            return true;
          }
          return selectedDependencies.any(
            (dependency) =>
                dependency.id == pack.id &&
                _versionNumber(dependency.version) ==
                    _versionNumber(pack.version),
          );
        })
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

bool _matchesOverride(
  DataPackManifestEntry pack,
  EmergencyOverrideManifest? override,
) {
  return override != null &&
      pack.id == override.id &&
      _versionNumber(pack.version) == _versionNumber(override.version);
}

void _protectVersion(
  Map<String, Set<String>> protectedVersionsByPackId, {
  required String id,
  required String version,
}) {
  protectedVersionsByPackId
      .putIfAbsent(id, () => <String>{})
      .add(_normalizedVersion(version));
}

String _normalizedVersion(String version) {
  return _versionNumber(version).toString();
}
