import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'catalog_database.dart';

class CatalogDatabaseOpener {
  CatalogDatabaseOpener({
    required this.databaseDirectory,
    required this.assetBundle,
  });

  static const indexAssetPath = 'assets/datapacks/index.json';

  final Directory databaseDirectory;
  final AssetBundle assetBundle;

  Future<CatalogDatabase> open() async {
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

  Future<void> _installBundledDataPacks(Directory datapackDirectory) async {
    final rawIndex = await assetBundle.loadString(indexAssetPath);
    final decoded = jsonDecode(rawIndex);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Invalid data pack index.');
    }
    final rawPacks = decoded['packs'];
    if (rawPacks is! List) {
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
    final expectedSha256 = pack['sha256'];
    if (id is! String || asset is! String) {
      throw const FormatException('Invalid data pack identity.');
    }

    final target = File(p.join(datapackDirectory.path, '$id.sqlite'));
    if (await target.exists()) {
      return;
    }

    final byteData = await assetBundle.load(asset);
    final compressedBytes = byteData.buffer.asUint8List(
      byteData.offsetInBytes,
      byteData.lengthInBytes,
    );
    if (expectedSha256 is String &&
        expectedSha256.isNotEmpty &&
        sha256.convert(compressedBytes).toString() != expectedSha256) {
      throw const FormatException('Data pack checksum mismatch.');
    }

    final databaseBytes = gzip.decode(compressedBytes);
    await target.writeAsBytes(databaseBytes, flush: true);
  }
}
