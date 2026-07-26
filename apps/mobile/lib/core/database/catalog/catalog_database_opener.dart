import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../datapack/atomic_file_replace.dart';
import '../../datapack/data_pack_file_integrity.dart';
import '../../datapack/data_pack_index.dart';
import '../../datapack/data_pack_update_state.dart';
import '../../datapack/emergency_override_repository.dart';
import 'catalog_database.dart';
import 'catalog_schema_diagnostics.dart';

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
  bool _openedBundledDataPack = false;
  String _openedArtifactIdentity = '';

  bool get openedBundledDataPack => _openedBundledDataPack;
  String get openedArtifactIdentity => _openedArtifactIdentity;

  Future<CatalogDatabase> open() async {
    _openedBundledDataPack = false;
    _openedArtifactIdentity = '';
    final installedDatabase = await _openInstalledCurrentDataPack();
    if (installedDatabase != null) {
      // 구제 DDL은 설치 팩 파일을 수정하므로 활성 팩이 확정된 뒤 이 한 곳에서만 실행한다(#2527).
      // known-good 후보를 훑는 동안에는 읽기 전용 판정만 하고 탐색 대상 파일은 건드리지 않는다.
      final plan = await installedDatabase.rescueMissingCatalogTables();
      await _refreshMutatedPackBaseline(
        database: installedDatabase,
        file: File(_openedArtifactIdentity),
        rescued: plan.hasRescuableMissingTables,
      );
      return installedDatabase;
    }

    final datapackDirectory = Directory(
      p.join(databaseDirectory.path, 'datapacks'),
    );
    await datapackDirectory.create(recursive: true);
    // 번들 팩·freshness 파일도 원자 교체 대상이라 중단 잔재가 남을 수 있다(#2532).
    await restoreInterruptedReplacements(datapackDirectory);
    final index = await _installBundledDataPacks(datapackDirectory);

    final database = CatalogDatabase.file(
      File(p.join(datapackDirectory.path, 'capital.sqlite')),
    );
    // 번들 경로도 설치 경로와 같은 구제를 거친다(#2527). 번들 팩은 마지막 대안이라
    // 거부할 상위 팩이 없으므로 구제만 하고 강등 판정은 하지 않는다.
    await database.rescueMissingCatalogTables();
    await database.seedBaselineIfEmpty();
    await _writeBundledFreshness(datapackDirectory, index);
    _openedBundledDataPack = true;
    _openedArtifactIdentity = p.normalize(
      File(p.join(datapackDirectory.path, 'capital.sqlite')).absolute.path,
    );
    return database;
  }

  /// 앱이 연 팩 파일을 스스로 바꿨으면 기대 해시 기준선을 다시 기록한다(#2532).
  ///
  /// 설치 팩 파일은 열기만 해도 내용이 바뀔 수 있다 — 구제 DDL(#2527)과 drift
  /// 마이그레이션(팩 `user_version`이 앱보다 낮을 때)이 그렇다. 기준선을 그대로 두면
  /// 재활성화 해시 대조가 정상 팩을 거부한다. 반대로 대조 시점마다 디스크 값을 그대로
  /// 받아 적으면 기준선이 오염되므로, **앱이 쓴 사실이 확인된 경우에만** 갱신한다.
  /// 갱신 비용(전체 해시 1회)도 그 경우에만 든다.
  ///
  /// 최종 선택된 팩만이 아니라 **판정 과정에서 연 모든 후보**가 대상이다. drift
  /// 마이그레이션은 후보를 판정하려고 던지는 첫 질의에서 이미 실행되므로, 거부돼 닫히는
  /// 후보(known-good 스캔·구제 불가 거부·override 후보)도 파일은 바뀐 채 남는다.
  Future<void> _refreshMutatedPackBaseline({
    required CatalogDatabase database,
    required File file,
    bool rescued = false,
  }) async {
    if (!rescued && !database.didRunSchemaMigration) {
      return;
    }
    if (file.path.isEmpty) {
      return;
    }
    try {
      await writeInstalledPackBaseline(file, await sha256OfFile(file));
    } on FileSystemException {
      // 기준선을 못 쓰면 다음 재활성화가 거부로 닫힌다. 열기 자체는 막지 않는다.
    }
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
    // pointer·설치 팩·기준선 어느 것이든 교체가 중단됐으면 먼저 정리한다(#2532).
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
      final file = _currentDataPackFile(decoded);
      if (file == null || !await file.exists()) {
        await _deleteIfExists(journal);
        return;
      }
      final expectedSha256 = decoded['sha256'];
      if (expectedSha256 is String &&
          expectedSha256.isNotEmpty &&
          await sha256OfFile(file) != expectedSha256) {
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
      if (!await _isUsableCatalogDatabase(database)) {
        return null;
      }
      // 빈 테이블 생성이 안전하지 않은 테이블이 빠져 있으면 이 팩을 열지 않고 known-good
      // 또는 번들로 강등한다(#2527). 판정은 읽기 전용이라 거부한 파일은 그대로 남는다.
      final plan = await database.planCatalogSchemaRescue();
      if (plan.isBlocked) {
        CatalogSchemaDiagnostics.instance.recordPackRejected(
          artifact: p.basename(file.path),
          blockingTableNames: plan.blockingMissingTables,
        );
        return null;
      }
      returned = true;
      _openedArtifactIdentity = p.normalize(file.absolute.path);
      return database;
    } finally {
      if (!returned) {
        // 판정하는 동안 drift 마이그레이션이 이 파일을 바꿨을 수 있다(#2532).
        // 거부한 후보도 기준선을 맞춰 두지 않으면 나중에 영구 거부로 남는다.
        await _refreshMutatedPackBaseline(database: database, file: file);
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
      // 번들 팩도 전량 적재 대신 스트리밍으로 판정한다 — 설치 팩이 없는 모든 콜드 스타트가
      // 지나는 경로라 팩 크기만큼 메모리를 한 번에 쓰면 안 된다(#2532).
      if (await sha256OfFile(target) == expectedSqliteSha256) {
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
    Directory datapackDirectory,
    DataPackIndex index,
  ) async {
    final freshness = evaluateDataPackFreshness(
      evaluationAt: _now().toUtc(),
      freshnessExpiresAt: index.freshnessExpiresAt,
    );
    final stale = freshness == DataPackFreshnessState.stale;
    final target = File(
      p.join(datapackDirectory.path, 'bundled-freshness.json'),
    );
    final temporary = File('${target.path}.installing');
    await temporary.writeAsString(
      '${jsonEncode({'status': stale ? 'STALE' : 'FRESH', 'freshnessExpiresAt': index.freshnessExpiresAt.toIso8601String(), 'reasonCode': stale ? 'BUNDLED_PACK_EXPIRED' : 'NONE', 'labelKo': stale ? '저장된 데이터 기준 · 갱신 필요' : ''})}\n',
      flush: true,
    );
    await _replaceFile(temporary, target);
  }

  /// 번들 팩을 디스크의 팩 파일로 되돌린다(#2532).
  ///
  /// [target]은 이 세션이 곧 열 카탈로그 DB 파일이다. `open()`이 번들 설치를 먼저 끝내고
  /// 그 뒤에 열므로 이 시점에는 아직 열려 있지 않지만, 이전 세션이나 홈 위젯 isolate가
  /// 같은 파일을 열고 있을 수 있다. 그래서 교체 실패 시 대상을 지우지 않고
  /// [replaceFileAtomically]가 직전 파일을 되돌리게 둔다 — 지웠다가 중단되면 카탈로그가
  /// 통째로 사라진다.
  Future<void> _replaceInstalledDataPack(
    File target,
    List<int> databaseBytes,
  ) async {
    final temporary = File('${target.path}.installing');
    if (await temporary.exists()) {
      await temporary.delete();
    }

    await temporary.writeAsBytes(databaseBytes, flush: true);
    await replaceFileAtomically(temporary: temporary, target: target);
  }

  Future<void> _replaceFile(File temporary, File target) async {
    await replaceFileAtomically(temporary: temporary, target: target);
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
