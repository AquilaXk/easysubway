import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/catalog/catalog_database.dart';
import '../database/user/user_database.dart' as user_db;
import 'data_pack_manifest.dart';

class DataPackInstaller {
  DataPackInstaller({
    required this.catalogDirectory,
    required this.userDatabase,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Directory catalogDirectory;
  final user_db.UserDatabase userDatabase;
  final DateTime Function() _now;

  Future<DataPackInstallResult> install({
    required DataPackManifestEntry pack,
    required List<int> compressedBytes,
  }) async {
    await catalogDirectory.create(recursive: true);
    final compressedHash = sha256.convert(compressedBytes).toString();
    if (compressedHash != pack.compressedSha256) {
      return const DataPackInstallResult(
        status: DataPackInstallStatus.rejected,
        reason: DataPackInstallRejectionReason.sha256Mismatch,
      );
    }

    late final List<int> sqliteBytes;
    try {
      sqliteBytes = gzip.decode(compressedBytes);
    } on FormatException {
      return const DataPackInstallResult(
        status: DataPackInstallStatus.rejected,
        reason: DataPackInstallRejectionReason.invalidArchive,
      );
    }

    if (sha256.convert(sqliteBytes).toString() != pack.sqliteSha256) {
      return const DataPackInstallResult(
        status: DataPackInstallStatus.rejected,
        reason: DataPackInstallRejectionReason.sqliteSha256Mismatch,
      );
    }

    final temporary = File(
      p.join(catalogDirectory.path, '${pack.id}-v${pack.version}.sqlite.tmp'),
    );
    final target = File(
      p.join(catalogDirectory.path, '${pack.id}-v${pack.version}.sqlite'),
    );
    await temporary.writeAsBytes(sqliteBytes, flush: true);
    final rejection = await _validateSqlite(temporary, pack);
    if (rejection != null) {
      await _deleteIfExists(temporary);
      return DataPackInstallResult(
        status: DataPackInstallStatus.rejected,
        reason: rejection,
      );
    }

    await _replaceFile(temporary, target);
    final pointer = InstalledDataPackPointer(
      id: pack.id,
      version: pack.version,
      path: target.path,
      sha256: pack.sqliteSha256,
      installedAt: _now().toUtc(),
    );
    await _writeCurrentPointer(pointer);
    await _pruneObsoletePacks(pack.id, keepVersionCount: 2);
    await userDatabase
        .into(userDatabase.installedDataPacks)
        .insertOnConflictUpdate(
          user_db.InstalledDataPacksCompanion.insert(
            packId: pack.id,
            version: pack.version,
            sha256: pack.sqliteSha256,
            installedAt: pointer.installedAt!,
          ),
        );

    return DataPackInstallResult(
      status: DataPackInstallStatus.installed,
      pointer: pointer,
    );
  }

  Future<InstalledDataPackPointer?> readCurrentPointer() async {
    final file = File(p.join(catalogDirectory.path, 'current.json'));
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    return InstalledDataPackPointer.fromJson(decoded);
  }

  Future<DataPackInstallRejectionReason?> _validateSqlite(
    File file,
    DataPackManifestEntry pack,
  ) async {
    final header = await file.openRead(0, 16).first;
    if (!_hasSqliteHeader(header)) {
      return DataPackInstallRejectionReason.invalidSqliteHeader;
    }

    final database = CatalogDatabase.file(file);
    try {
      final quickCheck = await database
          .customSelect('PRAGMA quick_check')
          .get();
      if (quickCheck.any((row) => row.data.values.first != 'ok')) {
        return DataPackInstallRejectionReason.quickCheckFailed;
      }
      final schemaVersion = await database
          .customSelect(
            "SELECT value FROM catalog_metadata WHERE key = 'schemaVersion'",
          )
          .getSingleOrNull();
      if (schemaVersion?.read<String>('value') != pack.schemaVersion) {
        return DataPackInstallRejectionReason.schemaVersionMismatch;
      }
      for (final table in pack.requiredTables) {
        final row = await database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
              variables: [Variable<String>(table)],
            )
            .getSingleOrNull();
        if (row == null) {
          return DataPackInstallRejectionReason.requiredTableMissing;
        }
      }
      for (final entry in pack.minimumTableRows.entries) {
        final rows = await database
            .customSelect('SELECT COUNT(*) AS count FROM ${entry.key}')
            .getSingle();
        if (rows.read<int>('count') < entry.value) {
          return DataPackInstallRejectionReason.minimumRowsMissing;
        }
      }
    } on Object {
      return DataPackInstallRejectionReason.quickCheckFailed;
    } finally {
      await database.close();
    }

    return null;
  }

  Future<void> _writeCurrentPointer(InstalledDataPackPointer pointer) async {
    final target = File(p.join(catalogDirectory.path, 'current.json'));
    final temporary = File('${target.path}.installing');
    await temporary.writeAsString(jsonEncode(pointer.toJson()), flush: true);
    await _replaceFile(temporary, target);
  }

  Future<void> _pruneObsoletePacks(
    String packId, {
    required int keepVersionCount,
  }) async {
    final packFiles = await catalogDirectory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => p.basename(file.path).startsWith('$packId-v'))
        .where((file) => p.extension(file.path) == '.sqlite')
        .toList();
    packFiles.sort((left, right) {
      return _versionNumber(right.path).compareTo(_versionNumber(left.path));
    });
    for (final file in packFiles.skip(keepVersionCount)) {
      await _deleteIfExists(file);
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

class DataPackInstallResult {
  const DataPackInstallResult({
    required this.status,
    this.reason,
    this.pointer,
  });

  final DataPackInstallStatus status;
  final DataPackInstallRejectionReason? reason;
  final InstalledDataPackPointer? pointer;
}

enum DataPackInstallStatus { installed, rejected }

enum DataPackInstallRejectionReason {
  invalidArchive,
  sha256Mismatch,
  sqliteSha256Mismatch,
  invalidSqliteHeader,
  quickCheckFailed,
  schemaVersionMismatch,
  requiredTableMissing,
  minimumRowsMissing,
}

class InstalledDataPackPointer {
  const InstalledDataPackPointer({
    required this.id,
    required this.version,
    required this.path,
    this.sha256,
    this.installedAt,
    this.reason,
  });

  factory InstalledDataPackPointer.fromJson(Map<String, Object?> json) {
    final installedAt = json['installedAt'];
    return InstalledDataPackPointer(
      id: _readString(json, 'id'),
      version: _readString(json, 'version'),
      path: _readString(json, 'path'),
      sha256: json['sha256'] is String ? json['sha256'] as String : null,
      installedAt: installedAt is String
          ? DateTime.tryParse(installedAt)
          : null,
      reason: json['reason'] is String ? json['reason'] as String : null,
    );
  }

  final String id;
  final String version;
  final String path;
  final String? sha256;
  final DateTime? installedAt;
  final String? reason;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'version': version,
      'path': path,
      if (sha256 != null) 'sha256': sha256,
      if (installedAt != null) 'installedAt': installedAt!.toIso8601String(),
      if (reason != null) 'reason': reason,
    };
  }
}

bool _hasSqliteHeader(List<int> header) {
  return header.length == 16 &&
      String.fromCharCodes(header.take(15)) == 'SQLite format 3' &&
      header[15] == 0;
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

String _readString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid data pack pointer.');
  }
  return value.trim();
}

int _versionNumber(String path) {
  final match = RegExp(r'-v(\d+)\.sqlite$').firstMatch(p.basename(path));
  if (match == null) {
    return 0;
  }
  return int.tryParse(match.group(1)!) ?? 0;
}
