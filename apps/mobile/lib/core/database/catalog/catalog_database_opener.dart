import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../datapack/data_pack_index.dart';
import '../../datapack/data_pack_update_state.dart';
import '../../datapack/emergency_override_repository.dart';
import 'catalog_database.dart';

class CatalogDatabaseOpener {
  CatalogDatabaseOpener({
    required this.databaseDirectory,
    required this.assetBundle,
    this.emergencyOverrideRepository,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const indexAssetPath = 'assets/datapacks/index.json';

  final Directory databaseDirectory;
  final AssetBundle assetBundle;
  final EmergencyOverrideRepository? emergencyOverrideRepository;
  final DateTime Function() _now;

  Future<CatalogDatabase> open() async {
    final installedDatabase = await _openInstalledCurrentDataPack();
    if (installedDatabase != null) {
      return installedDatabase;
    }

    final datapackDirectory = Directory(
      p.join(databaseDirectory.path, 'datapacks'),
    );
    await datapackDirectory.create(recursive: true);
    final index = await _installBundledDataPacks(datapackDirectory);

    final database = CatalogDatabase.file(
      File(p.join(datapackDirectory.path, 'capital.sqlite')),
    );
    await database.seedBaselineIfEmpty();
    await _writeBundledFreshness(database, index);
    return database;
  }

  Future<CatalogDatabase?> _openInstalledCurrentDataPack() async {
    await _recoverCurrentPointerJournal();
    final overrideDatabase = await _openEmergencyOverrideDataPack();
    if (overrideDatabase != null) {
      return overrideDatabase;
    }

    final pointer = File(
      p.join(databaseDirectory.path, 'catalog', 'current.json'),
    );
    if (!await pointer.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await pointer.readAsString());
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final preferredPackId = _pointerPackId(decoded);
      final preferredVersionLimit = _pointerVersionNumber(decoded);
      final file = _currentDataPackFile(decoded);
      if (file == null) {
        if (preferredPackId == null) {
          return null;
        }
        return _openKnownGoodInstalledDataPack(
          preferredPackId: preferredPackId,
          maximumVersion: preferredVersionLimit,
        );
      }
      if (!await file.exists()) {
        if (preferredPackId == null) {
          return null;
        }
        return _openKnownGoodInstalledDataPack(
          preferredPackId: preferredPackId,
          maximumVersion: preferredVersionLimit,
        );
      }
      final database = await _openUsableCatalogDatabase(file);
      if (database != null || preferredPackId == null) {
        return database;
      }
      return _openKnownGoodInstalledDataPack(
        preferredPackId: preferredPackId,
        maximumVersion: preferredVersionLimit,
      );
    } on Object {
      return null;
    }
  }

  Future<CatalogDatabase?> _openKnownGoodInstalledDataPack({
    String? preferredPackId,
    int? maximumVersion,
  }) async {
    final catalogDirectory = Directory(
      p.join(databaseDirectory.path, 'catalog'),
    );
    if (!await catalogDirectory.exists()) {
      return null;
    }
    final candidates = await catalogDirectory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where(
          (file) => RegExp(r'-v\d+\.sqlite$').hasMatch(p.basename(file.path)),
        )
        .where(
          (file) =>
              preferredPackId == null ||
              p.basename(file.path).startsWith('$preferredPackId-v'),
        )
        .where(
          (file) =>
              maximumVersion == null ||
              _installedPackVersion(file) <= maximumVersion,
        )
        .toList();
    candidates.sort((left, right) {
      return _installedPackVersion(
        right,
      ).compareTo(_installedPackVersion(left));
    });
    for (final candidate in candidates) {
      final database = await _openUsableCatalogDatabase(candidate);
      if (database != null) {
        return database;
      }
    }
    return null;
  }

  Future<void> _recoverCurrentPointerJournal() async {
    final catalogDirectory = Directory(
      p.join(databaseDirectory.path, 'catalog'),
    );
    final journal = File(
      p.join(catalogDirectory.path, 'current.json.installing'),
    );
    if (!await journal.exists()) {
      return;
    }
    try {
      final decoded = jsonDecode(await journal.readAsString());
      if (decoded is! Map<String, Object?>) {
        await _deleteIfExists(journal);
        return;
      }
      final file = _currentDataPackFile(decoded);
      if (file == null || !await file.exists()) {
        await _deleteIfExists(journal);
        return;
      }
      final expectedSha256 = decoded['sha256'];
      if (expectedSha256 is String &&
          expectedSha256.isNotEmpty &&
          sha256.convert(await file.readAsBytes()).toString() !=
              expectedSha256) {
        await _deleteIfExists(journal);
        return;
      }
      await _replaceFile(
        journal,
        File(p.join(catalogDirectory.path, 'current.json')),
      );
    } on Object {
      await _deleteIfExists(journal);
    }
  }

  String? _pointerPackId(Map<String, Object?> pointer) {
    final id = pointer['id'];
    if (id is String && id.trim().isNotEmpty) {
      return id.trim();
    }
    return null;
  }

  int? _pointerVersionNumber(Map<String, Object?> pointer) {
    final version = pointer['version'];
    if (version is! String || version.trim().isEmpty) {
      return null;
    }
    return int.tryParse(version.trim());
  }

  File? _currentDataPackFile(Map<String, Object?> pointer) {
    final id = pointer['id'];
    final version = pointer['version'];
    if (id is String &&
        id.trim().isNotEmpty &&
        version is String &&
        version.trim().isNotEmpty) {
      return File(
        p.join(
          databaseDirectory.path,
          'catalog',
          '${id.trim()}-v${version.trim()}.sqlite',
        ),
      );
    }

    final path = pointer['path'];
    if (path is String && path.trim().isNotEmpty) {
      return File(path.trim());
    }
    return null;
  }

  Future<CatalogDatabase?> _openEmergencyOverrideDataPack() async {
    final repository = emergencyOverrideRepository;
    if (repository == null) {
      return null;
    }
    try {
      final override = await repository.readOverride();
      if (override == null) {
        return null;
      }
      final file = File(
        p.join(
          databaseDirectory.path,
          'catalog',
          '${override.id}-v${override.version}.sqlite',
        ),
      );
      if (!await file.exists()) {
        return null;
      }
      return await _openUsableCatalogDatabase(file);
    } on Object {
      return null;
    }
  }

  Future<CatalogDatabase?> _openUsableCatalogDatabase(File file) async {
    final database = CatalogDatabase.file(file);
    var returned = false;
    try {
      if (await _isUsableCatalogDatabase(database)) {
        returned = true;
        return database;
      }
      return null;
    } finally {
      if (!returned) {
        await database.close();
      }
    }
  }

  Future<bool> _isUsableCatalogDatabase(CatalogDatabase database) async {
    final quickCheck = await database.customSelect('PRAGMA quick_check').get();
    if (quickCheck.any((row) => row.data.values.first != 'ok')) {
      return false;
    }
    final schemaVersion = await database
        .customSelect(
          "SELECT value FROM catalog_metadata WHERE key = 'schemaVersion'",
        )
        .getSingleOrNull();
    return schemaVersion != null;
  }

  Future<DataPackIndex> _installBundledDataPacks(
    Directory datapackDirectory,
  ) async {
    final rawIndex = await assetBundle.loadString(indexAssetPath);
    final decoded = jsonDecode(rawIndex);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid data pack index.');
    }
    final index = DataPackIndex.fromJson(decoded);

    for (final pack in index.packs) {
      await _installDataPack(pack, datapackDirectory);
    }
    return index;
  }

  Future<void> _installDataPack(
    DataPackIndexEntry pack,
    Directory datapackDirectory,
  ) async {
    final id = pack.id;
    final asset = pack.asset;
    final expectedCompressedSha256 = pack.sha256;
    final expectedSqliteSha256 = pack.sqliteSha256;

    final target = File(p.join(datapackDirectory.path, '$id.sqlite'));
    if (await target.exists()) {
      final installedBytes = await target.readAsBytes();
      if (sha256.convert(installedBytes).toString() == expectedSqliteSha256) {
        return;
      }
    }

    final byteData = await assetBundle.load(asset);
    final compressedBytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    if (sha256.convert(compressedBytes).toString() !=
        expectedCompressedSha256) {
      throw const FormatException('Data pack checksum mismatch.');
    }

    final databaseBytes = gzip.decode(compressedBytes);
    if (sha256.convert(databaseBytes).toString() != expectedSqliteSha256) {
      throw const FormatException('Data pack sqlite checksum mismatch.');
    }

    await _replaceInstalledDataPack(target, databaseBytes);
  }

  Future<void> _writeBundledFreshness(
    CatalogDatabase database,
    DataPackIndex index,
  ) async {
    final freshness = evaluateDataPackFreshness(
      evaluationAt: _now().toUtc(),
      freshnessExpiresAt: index.freshnessExpiresAt,
    );
    final stale = freshness == DataPackFreshnessState.stale;
    await database.batch((batch) {
      batch.insertAllOnConflictUpdate(database.catalogMetadata, [
        CatalogMetadataCompanion.insert(
          key: 'datapack.freshness.status',
          value: stale ? 'STALE' : 'FRESH',
        ),
        CatalogMetadataCompanion.insert(
          key: 'datapack.freshness.expiresAt',
          value: index.freshnessExpiresAt.toIso8601String(),
        ),
        CatalogMetadataCompanion.insert(
          key: 'datapack.freshness.reasonCode',
          value: stale ? 'BUNDLED_PACK_EXPIRED' : 'NONE',
        ),
        CatalogMetadataCompanion.insert(
          key: 'datapack.freshness.labelKo',
          value: stale ? '저장된 데이터 기준 · 갱신 필요' : '',
        ),
      ]);
    });
  }

  Future<void> _replaceInstalledDataPack(
    File target,
    List<int> databaseBytes,
  ) async {
    final temporary = File('${target.path}.installing');
    if (await temporary.exists()) {
      await temporary.delete();
    }

    await temporary.writeAsBytes(databaseBytes, flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) {
        await target.delete();
      }
      await temporary.rename(target.path);
    }
  }

  Future<void> _replaceFile(File temporary, File target) async {
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      await _deleteIfExists(target);
      await temporary.rename(target.path);
    }
  }
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

int _installedPackVersion(File file) {
  final match = RegExp(r'-v(\d+)\.sqlite$').firstMatch(p.basename(file.path));
  if (match == null) {
    return 0;
  }
  return int.tryParse(match.group(1)!) ?? 0;
}
