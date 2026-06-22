import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../datapack/emergency_override_repository.dart';
import 'catalog_database.dart';

class CatalogDatabaseOpener {
  CatalogDatabaseOpener({
    required this.databaseDirectory,
    required this.assetBundle,
    this.emergencyOverrideRepository,
  });

  static const indexAssetPath = 'assets/datapacks/index.json';

  final Directory databaseDirectory;
  final AssetBundle assetBundle;
  final EmergencyOverrideRepository? emergencyOverrideRepository;

  Future<CatalogDatabase> open() async {
    final installedDatabase = await _openInstalledCurrentDataPack();
    if (installedDatabase != null) {
      return installedDatabase;
    }

    final datapackDirectory = Directory(
      p.join(databaseDirectory.path, 'datapacks'),
    );
    await datapackDirectory.create(recursive: true);
    await _installBundledDataPacks(datapackDirectory);

    final database = CatalogDatabase.file(
      File(p.join(datapackDirectory.path, 'capital.sqlite')),
    );
    await database.seedBaselineIfEmpty();
    return database;
  }

  Future<CatalogDatabase?> _openInstalledCurrentDataPack() async {
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
      final file = _currentDataPackFile(decoded);
      if (file == null) {
        return null;
      }
      if (!await file.exists()) {
        return null;
      }
      return await _openUsableCatalogDatabase(file);
    } on Object {
      return null;
    }
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
        await database.seedBaselineIfEmpty();
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

  Future<void> _installBundledDataPacks(Directory datapackDirectory) async {
    final rawIndex = await assetBundle.loadString(indexAssetPath);
    final decoded = jsonDecode(rawIndex);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid data pack index.');
    }
    final rawPacks = decoded['packs'];
    if (rawPacks is! List<Object?>) {
      throw const FormatException('Invalid data pack list.');
    }

    for (final rawPack in rawPacks) {
      if (rawPack is! Map<String, Object?>) {
        throw const FormatException('Invalid data pack entry.');
      }
      await _installDataPack(rawPack, datapackDirectory);
    }
  }

  Future<void> _installDataPack(
    Map<String, Object?> pack,
    Directory datapackDirectory,
  ) async {
    final id = pack['id'];
    final asset = pack['asset'];
    final expectedCompressedSha256 = pack['sha256'];
    final expectedSqliteSha256 = pack['sqliteSha256'];
    if (id is! String || asset is! String) {
      throw const FormatException('Invalid data pack identity.');
    }

    final target = File(p.join(datapackDirectory.path, '$id.sqlite'));
    if (await target.exists()) {
      if (expectedSqliteSha256 is! String || expectedSqliteSha256.isEmpty) {
        return;
      }

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
    if (expectedCompressedSha256 is String &&
        expectedCompressedSha256.isNotEmpty &&
        sha256.convert(compressedBytes).toString() !=
            expectedCompressedSha256) {
      throw const FormatException('Data pack checksum mismatch.');
    }

    final databaseBytes = gzip.decode(compressedBytes);
    if (expectedSqliteSha256 is String &&
        expectedSqliteSha256.isNotEmpty &&
        sha256.convert(databaseBytes).toString() != expectedSqliteSha256) {
      throw const FormatException('Data pack sqlite checksum mismatch.');
    }

    await _replaceInstalledDataPack(target, databaseBytes);
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
}
