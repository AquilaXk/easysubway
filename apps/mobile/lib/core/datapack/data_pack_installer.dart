import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../database/user/user_database.dart' as user_db;
import 'data_pack_manifest.dart';

/// Enforces the data-pack pointer contract.
///
/// A pack can replace `current.json` only after archive, hash, schema, table,
/// and quick-check validation. Rejected installs leave the active pointer and
/// user-owned database rows untouched.
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
    Set<String> protectedVersions = const {},
    bool activateCurrent = true,
  }) async {
    await catalogDirectory.create(recursive: true);
    final expectedSizeBytes = pack.sizeBytes;
    if (expectedSizeBytes != null &&
        compressedBytes.length != expectedSizeBytes) {
      return const DataPackInstallResult(
        status: DataPackInstallStatus.rejected,
        reason: DataPackInstallRejectionReason.sizeBytesMismatch,
      );
    }
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
    if (activateCurrent) {
      await activateCurrentPointer(pointer);
      await pruneObsoletePacks(
        pack.id,
        keepVersionCount: 2,
        protectedVersions: protectedVersions,
      );
    }
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

  Future<InstalledDataPackPointer?> readInstalledPointer({
    required String id,
    required String version,
  }) async {
    final target = File(p.join(catalogDirectory.path, '$id-v$version.sqlite'));
    if (!await target.exists()) {
      return _readInstalledPointerByNumericVersion(id: id, version: version);
    }
    return _pointerForInstalledFile(file: target, id: id, version: version);
  }

  Future<InstalledDataPackPointer?> _readInstalledPointerByNumericVersion({
    required String id,
    required String version,
  }) async {
    final requestedVersion = int.tryParse(version);
    if (requestedVersion == null || !await catalogDirectory.exists()) {
      return null;
    }
    final candidates = await catalogDirectory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .where((file) => _versionNumber(file.path) == requestedVersion)
        .where((file) => _versionText(file.path, id) != null)
        .toList();
    candidates.sort((left, right) {
      return p.basename(left.path).compareTo(p.basename(right.path));
    });
    if (candidates.isEmpty) {
      return null;
    }
    final candidate = candidates.first;
    final candidateVersion = _versionText(candidate.path, id);
    if (candidateVersion == null) {
      return null;
    }
    return _pointerForInstalledFile(
      file: candidate,
      id: id,
      version: candidateVersion,
    );
  }

  Future<InstalledDataPackPointer> _pointerForInstalledFile({
    required File file,
    required String id,
    required String version,
  }) async {
    return InstalledDataPackPointer(
      id: id,
      version: version,
      path: file.path,
      sha256: sha256.convert(await file.readAsBytes()).toString(),
    );
  }

  Future<void> activateCurrentPointer(InstalledDataPackPointer pointer) async {
    await _writeCurrentPointer(pointer);
  }

  Future<void> pruneObsoletePacks(
    String packId, {
    required int keepVersionCount,
    required Set<String> protectedVersions,
  }) async {
    await _pruneObsoletePacks(
      packId,
      keepVersionCount: keepVersionCount,
      protectedVersions: protectedVersions,
    );
  }

  Future<DataPackInstallRejectionReason?> _validateSqlite(
    File file,
    DataPackManifestEntry pack,
  ) async {
    final header = await file
        .openRead(0, 16)
        .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
    if (!_hasSqliteHeader(header)) {
      return DataPackInstallRejectionReason.invalidSqliteHeader;
    }

    final database = sqlite.sqlite3.open(
      file.path,
      mode: sqlite.OpenMode.readOnly,
    );
    try {
      final quickCheck = database.select('PRAGMA quick_check');
      if (quickCheck.any((row) => row.values.first != 'ok')) {
        return DataPackInstallRejectionReason.quickCheckFailed;
      }
      final schemaVersion = database.select(
        "SELECT value FROM catalog_metadata WHERE key = 'schemaVersion'",
      );
      if (schemaVersion.isEmpty ||
          schemaVersion.first['value'] != pack.schemaVersion) {
        return DataPackInstallRejectionReason.schemaVersionMismatch;
      }
      for (final table in pack.requiredTables) {
        final rows = database.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          [table],
        );
        if (rows.isEmpty) {
          return DataPackInstallRejectionReason.requiredTableMissing;
        }
      }
      for (final entry in pack.minimumTableRows.entries) {
        final rows = database.select(
          'SELECT COUNT(*) AS count FROM ${_quotedSqlIdentifier(entry.key)}',
        );
        if ((rows.first['count'] as int) < entry.value) {
          return DataPackInstallRejectionReason.minimumRowsMissing;
        }
      }
    } on Object {
      return DataPackInstallRejectionReason.quickCheckFailed;
    } finally {
      database.close();
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
    required Set<String> protectedVersions,
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
    var keptUnprotectedCount = 0;
    for (final file in packFiles) {
      final version = _versionNumber(file.path).toString();
      if (protectedVersions.contains(version)) {
        continue;
      }
      keptUnprotectedCount++;
      if (keptUnprotectedCount <= keepVersionCount) {
        continue;
      }
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
  sizeBytesMismatch,
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

String _quotedSqlIdentifier(String value) => '"${value.replaceAll('"', '""')}"';

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

String? _versionText(String path, String packId) {
  final pattern = RegExp('^${RegExp.escape(packId)}-v([0-9]+)\\.sqlite\$');
  return pattern.firstMatch(p.basename(path))?.group(1);
}
