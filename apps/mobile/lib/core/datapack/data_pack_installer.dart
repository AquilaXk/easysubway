import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../database/catalog/catalog_database.dart';
import '../database/catalog/catalog_schema_diagnostics.dart';
import '../database/user/user_database.dart' as user_db;
import 'atomic_file_replace.dart';
import 'data_pack_file_integrity.dart';
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
    final compressedFile = File(
      p.join(
        catalogDirectory.path,
        '${pack.id}-v${pack.version}.sqlite.gz.tmp',
      ),
    );
    await compressedFile.writeAsBytes(compressedBytes, flush: true);
    return installFromCompressedFile(
      pack: pack,
      compressedFile: compressedFile,
      protectedVersions: protectedVersions,
      activateCurrent: activateCurrent,
    );
  }

  Future<DataPackInstallResult> installFromCompressedFile({
    required DataPackManifestEntry pack,
    required File compressedFile,
    Set<String> protectedVersions = const {},
    bool activateCurrent = true,
  }) async {
    await catalogDirectory.create(recursive: true);
    final expectedSizeBytes = pack.sizeBytes;
    final compressedLength = await compressedFile.length();
    if (expectedSizeBytes != null && compressedLength != expectedSizeBytes) {
      await _deleteIfExists(compressedFile);
      return const DataPackInstallResult(
        status: DataPackInstallStatus.rejected,
        reason: DataPackInstallRejectionReason.sizeBytesMismatch,
      );
    }
    final compressedHash = await sha256OfFile(compressedFile);
    if (compressedHash != pack.compressedSha256) {
      await _deleteIfExists(compressedFile);
      return const DataPackInstallResult(
        status: DataPackInstallStatus.rejected,
        reason: DataPackInstallRejectionReason.sha256Mismatch,
      );
    }

    final temporary = File(
      p.join(catalogDirectory.path, '${pack.id}-v${pack.version}.sqlite.tmp'),
    );
    final sqliteHash = await _inflateGzipToFile(
      compressedFile: compressedFile,
      targetFile: temporary,
    );
    await _deleteIfExists(compressedFile);
    if (sqliteHash == null) {
      await _deleteIfExists(temporary);
      return const DataPackInstallResult(
        status: DataPackInstallStatus.rejected,
        reason: DataPackInstallRejectionReason.invalidArchive,
      );
    }

    if (sqliteHash != pack.sqliteSha256) {
      await _deleteIfExists(temporary);
      return const DataPackInstallResult(
        status: DataPackInstallStatus.rejected,
        reason: DataPackInstallRejectionReason.sqliteSha256Mismatch,
      );
    }

    final target = File(
      p.join(catalogDirectory.path, '${pack.id}-v${pack.version}.sqlite'),
    );
    final rejection = await _validateSqlite(temporary, pack);
    if (rejection != null) {
      await _deleteIfExists(temporary);
      return DataPackInstallResult(
        status: DataPackInstallStatus.rejected,
        reason: rejection,
      );
    }

    await _replaceFile(temporary, target);
    // 재활성화 대조의 기준선(#2532). 매니페스트가 선언하고 방금 실제 파일과 대조한 값이다.
    await writeInstalledPackBaseline(target, pack.sqliteSha256);
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
    await recoverInstallJournal();
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

  /// 이미 설치된 팩을 다시 가리킬 때 쓸 pointer(#2532).
  ///
  /// 디스크 해시를 기대 해시와 대조하고 어긋나면 pointer를 만들지 않는다. 대조할 기대
  /// 해시가 하나도 없으면 "확인할 수 없음"이므로 역시 만들지 않는다 — 디스크 값을 그대로
  /// 정답으로 기록하면 이후 검증의 기준선까지 오염된다.
  ///
  /// 결과가 [InstalledDataPackLookup]인 이유: 설치본 없음·기준선 없음·해시 불일치는
  /// 호출자가 다르게 처리해야 한다. 셋을 `null` 하나로 뭉치면 예컨대 긴급 override 해제
  /// 판단이 "확인 못 함"과 "확인해 보니 다름"을 구분하지 못한다.
  ///
  /// [expectedSha256]에는 호출자가 서명된 매니페스트에서 읽은 `sqliteSha256`을 넘긴다.
  /// 그 값이 있으면 **그 값만** 정답으로 쓴다(단말 기록으로 내려가지 않는다). 앱이 파일을
  /// 바꿔 기준선을 다시 쓴 경우에도 매니페스트 기준으로는 그 파일이 더 이상 배포본이
  /// 아니므로, 재활성화 대신 재설치 경로로 되돌리는 쪽이 맞다. 매니페스트 값이 없으면
  /// 설치 시 기록한 기준선 → 저장된 pointer → `installed_data_packs` 레코드 순으로 찾는다.
  Future<InstalledDataPackLookup> readInstalledPointer({
    required String id,
    required String version,
    String? expectedSha256,
  }) async {
    final target = File(p.join(catalogDirectory.path, '$id-v$version.sqlite'));
    // 교체가 중단돼 직전 팩만 남았으면 되살린다(#2532).
    await restoreReplacedTarget(target);
    if (!await target.exists()) {
      return _readInstalledPointerByNumericVersion(
        id: id,
        version: version,
        expectedSha256: expectedSha256,
      );
    }
    return _pointerForInstalledFile(
      file: target,
      id: id,
      version: version,
      expectedSha256: expectedSha256,
    );
  }

  Future<InstalledDataPackLookup> _readInstalledPointerByNumericVersion({
    required String id,
    required String version,
    String? expectedSha256,
  }) async {
    final requestedVersion = int.tryParse(version);
    if (requestedVersion == null || !await catalogDirectory.exists()) {
      return const InstalledDataPackLookup.rejected(
        InstalledDataPackRejection.notInstalled,
      );
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
      return const InstalledDataPackLookup.rejected(
        InstalledDataPackRejection.notInstalled,
      );
    }
    final candidate = candidates.first;
    final candidateVersion = _versionText(candidate.path, id);
    if (candidateVersion == null) {
      return const InstalledDataPackLookup.rejected(
        InstalledDataPackRejection.notInstalled,
      );
    }
    return _pointerForInstalledFile(
      file: candidate,
      id: id,
      version: candidateVersion,
      expectedSha256: expectedSha256,
    );
  }

  Future<InstalledDataPackLookup> _pointerForInstalledFile({
    required File file,
    required String id,
    required String version,
    required String? expectedSha256,
  }) async {
    // 매니페스트 값은 형식이 깨져 있어도 단말 기록으로 내려가지 않는다. 서명된 값이 있는데
    // 대조에 실패하면 그것이 결론이다.
    final expected = expectedSha256 != null
        ? expectedSha256.trim().toLowerCase()
        : await _recordedExpectedSha256(file: file, id: id, version: version);
    final actual = await sha256OfFile(file);
    if (expected == null || expected != actual) {
      CatalogSchemaDiagnostics.instance.recordPackIntegrityRejected(
        artifact: p.basename(file.path),
        expectedSha256: expected,
        actualSha256: actual,
      );
      return InstalledDataPackLookup.rejected(
        expected == null
            ? InstalledDataPackRejection.baselineMissing
            : InstalledDataPackRejection.sha256Mismatch,
      );
    }
    return InstalledDataPackLookup.found(
      InstalledDataPackPointer(
        id: id,
        version: version,
        path: file.path,
        sha256: actual,
      ),
    );
  }

  /// 단말에 남아 있는 기대 해시. 기준선 파일이 원본이고, 그 파일이 없는 기존 설치를 위해
  /// 저장된 pointer와 설치 레코드를 차례로 본다. 세 단 모두 같은 형식 정규화를 거친다 —
  /// 한 단만 무검증으로 두면 형식이 깨진 값이 "어떤 파일과도 일치할 수 없는 기대값"이 되어
  /// 그 버전이 영구히 거부된다.
  Future<String?> _recordedExpectedSha256({
    required File file,
    required String id,
    required String version,
  }) async {
    final baseline = await readInstalledPackBaseline(file);
    if (baseline != null) {
      return baseline;
    }
    final pointer = await _readStoredPointer();
    if (pointer != null && pointer.id == id && pointer.version == version) {
      final storedSha256 = normalizedSha256Text(pointer.sha256);
      if (storedSha256 != null) {
        return storedSha256;
      }
    }
    final record = await (userDatabase.select(
      userDatabase.installedDataPacks,
    )..where((row) => row.packId.equals(id))).getSingleOrNull();
    if (record != null && record.version == version) {
      return normalizedSha256Text(record.sha256);
    }
    return null;
  }

  Future<InstalledDataPackPointer?> _readStoredPointer() async {
    final file = File(p.join(catalogDirectory.path, 'current.json'));
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      return InstalledDataPackPointer.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Future<void> activateCurrentPointer(InstalledDataPackPointer pointer) async {
    await _writeCurrentPointer(pointer);
  }

  Future<void> recoverInstallJournal() async {
    // 교체가 중단돼 남은 잔재를 먼저 정리한다(#2532). pointer·설치 팩·기준선이 모두
    // 대상이라 이름별로 부르지 않고 카탈로그 디렉토리를 한 번 훑는다.
    await restoreInterruptedReplacements(catalogDirectory);
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
      final pointer = InstalledDataPackPointer.fromJson(decoded);
      final file = File(pointer.path);
      if (!await file.exists()) {
        await _deleteIfExists(journal);
        return;
      }
      final expectedSha256 = pointer.sha256;
      if (expectedSha256 != null &&
          expectedSha256 != await sha256OfFile(file)) {
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
      final userVersion = database.select('PRAGMA user_version').first;
      final catalogUserVersion = userVersion['user_version'];
      if (catalogUserVersion is! int ||
          catalogUserVersion > catalogDatabaseSchemaVersion) {
        return DataPackInstallRejectionReason.unsupportedCatalogUserVersion;
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
      // 교체 잔재(`<pack>.previous`)는 정리 필터(`.sqlite`)에 걸리지 않아 여기서 함께
      // 지우지 않으면 팩 한 벌 크기로 영구히 남는다.
      await _deleteIfExists(replacedTargetBackupFile(file));
      await deleteInstalledPackBaseline(file);
    }
  }

  Future<void> _replaceFile(File temporary, File target) async {
    await replaceFileAtomically(temporary: temporary, target: target);
  }
}

Future<String?> _inflateGzipToFile({
  required File compressedFile,
  required File targetFile,
}) async {
  final output = Sha256DigestSink();
  final input = sha256.startChunkedConversion(output);
  final sink = targetFile.openWrite();
  try {
    await for (final chunk in compressedFile.openRead().transform(
      gzip.decoder,
    )) {
      input.add(chunk);
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();
    input.close();
    return output.value.toString();
  } on FormatException {
    await sink.close();
    return null;
  }
}

/// 설치본 재활성화 조회 결과(#2532).
///
/// pointer가 있으면 대조를 통과한 것이고, 없으면 [rejection]이 사유를 담는다.
class InstalledDataPackLookup {
  const InstalledDataPackLookup.found(InstalledDataPackPointer this.pointer)
    : rejection = null;

  const InstalledDataPackLookup.rejected(
    InstalledDataPackRejection this.rejection,
  ) : pointer = null;

  final InstalledDataPackPointer? pointer;
  final InstalledDataPackRejection? rejection;
}

/// 재활성화를 거부한 사유(#2532).
enum InstalledDataPackRejection {
  /// 그 버전의 설치 파일이 없다.
  notInstalled,

  /// 대조할 기대 해시가 단말에 없어 무결성을 판정하지 못했다.
  baselineMissing,

  /// 디스크 해시가 기대 해시와 다르다.
  sha256Mismatch,
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
  unsupportedCatalogUserVersion,
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
