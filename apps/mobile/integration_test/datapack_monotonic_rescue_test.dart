import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/core/database/catalog/catalog_database.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/data_pack_client.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_installer.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_manifest.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqlite3/sqlite3.dart';

const _rcManifestSha256 = String.fromEnvironment(
  'EASYSUBWAY_RC_MANIFEST_SHA256',
);
const _rcReleaseSequence = int.fromEnvironment(
  'EASYSUBWAY_RC_RELEASE_SEQUENCE',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '실제 Android에서 failed release 뒤 monotonic rescue가 known-good 내용을 복구한다',
    (_) async {
      expect(_rcManifestSha256, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(_rcReleaseSequence, greaterThanOrEqualTo(3));
      final directory = await Directory.systemTemp.createTemp(
        'easysubway-android-monotonic-rescue-',
      );
      final rcBundle =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/datapacks/prelaunch/android-rc-bundle.json',
                ),
              )
              as Map<String, Object?>;
      final rcManifestBytes = base64Decode(
        rcBundle['manifestBytesBase64']! as String,
      );
      final rcArtifactBytes = base64Decode(
        rcBundle['artifactBytesBase64']! as String,
      );
      final computedManifestSha256 = sha256.convert(rcManifestBytes).toString();
      final computedArtifactSha256 = sha256.convert(rcArtifactBytes).toString();
      expect(computedManifestSha256, _rcManifestSha256);
      expect(computedManifestSha256, rcBundle['manifestSha256']);
      expect(computedArtifactSha256, rcBundle['artifactSha256']);
      final publicKeyJson = rcBundle['publicKey']! as Map<String, Object?>;
      final rcManifest = DataPackManifest.fromJson(
        jsonDecode(utf8.decode(rcManifestBytes)) as Map<String, Object?>,
        productionSigningPublicKey: DataPackSigningPublicKey(
          modulusBase64Url: publicKeyJson['modulusBase64Url']! as String,
          exponentBase64Url: publicKeyJson['exponentBase64Url']! as String,
          keyId: publicKeyJson['keyId']! as String,
        ),
      );
      expect(rcManifest.releaseSequence, _rcReleaseSequence);
      final rcPack = rcManifest.packs.singleWhere(
        (pack) => pack.compressedSha256 == computedArtifactSha256,
      );
      final rcSqliteBytes = gzip.decode(rcArtifactBytes);
      expect(sha256.convert(rcSqliteBytes).toString(), rcPack.sqliteSha256);
      final rcSqliteFile = File('${directory.path}/actual-rc.sqlite');
      await rcSqliteFile.writeAsBytes(rcSqliteBytes, flush: true);
      final rcSqlite = sqlite3.open(rcSqliteFile.path, mode: OpenMode.readOnly);
      try {
        expect(rcSqlite.select('PRAGMA quick_check').first.values.first, 'ok');
        for (final table in rcPack.requiredTables) {
          expect(
            rcSqlite.select(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
              [table],
            ),
            isNotEmpty,
          );
        }
      } finally {
        rcSqlite.close();
      }
      final userDatabase = user_db.UserDatabase.memory();
      final catalogDirectory = Directory('${directory.path}/catalog');
      final knownGoodSqliteBytes = await _catalogSqliteBytesWithMarker(
        directory,
        fileName: 'known-good.sqlite',
        marker: 'known-good',
      );
      final failedSqliteBytes = await _catalogSqliteBytesWithMarker(
        directory,
        fileName: 'failed.sqlite',
        marker: 'failed',
      );
      final knownGoodCompressedBytes = gzip.encode(knownGoodSqliteBytes);
      final failedCompressedBytes = gzip.encode(failedSqliteBytes);
      final corruptBytes = <int>[1, 2, 3, 4];
      final knownGoodSequence = _rcReleaseSequence - 2;
      final failedSequence = _rcReleaseSequence - 1;
      var now = DateTime.utc(2026, 7, 17);
      var manifestJson = _signedV2PackManifest(
        sequence: knownGoodSequence,
        version: '18',
        compressedBytes: knownGoodCompressedBytes,
        sqliteBytes: knownGoodSqliteBytes,
      );
      DataPackManifest.fromJson(manifestJson);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        switch (request.uri.path) {
          case '/datapacks/catalog/current.json':
            request.response
              ..statusCode = HttpStatus.ok
              ..headers.contentType = ContentType.json
              ..write(jsonEncode(manifestJson))
              ..close();
          case '/datapacks/catalog/capital-v18.sqlite.gz':
            request.response
              ..statusCode = HttpStatus.ok
              ..add(knownGoodCompressedBytes)
              ..close();
          case '/datapacks/catalog/capital-v19.sqlite.gz':
            request.response
              ..statusCode = HttpStatus.ok
              ..add(failedCompressedBytes)
              ..close();
          case '/datapacks/catalog/capital-v20.sqlite.gz':
            request.response
              ..statusCode = HttpStatus.ok
              ..add(corruptBytes)
              ..close();
          default:
            request.response
              ..statusCode = HttpStatus.notFound
              ..close();
        }
      });
      final stateRepository = DataPackUpdateStateRepository(
        userDatabase: userDatabase,
        now: () => now,
      );
      final installer = DataPackInstaller(
        catalogDirectory: catalogDirectory,
        userDatabase: userDatabase,
      );
      final updater = DataPackUpdater(
        client: DataPackClient(
          manifestUri: Uri.parse(
            'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
          ),
          stateRepository: stateRepository,
          now: () => now,
        ),
        installer: installer,
        now: () => now,
      );

      try {
        await updater.checkForUpdates();
        manifestJson = _signedV2PackManifest(
          sequence: failedSequence,
          version: '19',
          compressedBytes: failedCompressedBytes,
          sqliteBytes: failedSqliteBytes,
        );
        now = now.add(const Duration(seconds: 2));
        await updater.checkForUpdates();
        expect((await installer.readCurrentPointer())?.version, '19');

        manifestJson = _signedV2PackManifest(
          sequence: _rcReleaseSequence,
          version: '18',
          compressedBytes: knownGoodCompressedBytes,
          sqliteBytes: knownGoodSqliteBytes,
          rollbackProvenance: {
            'kind': 'MONOTONIC_RESCUE',
            'currentReleaseSequence': failedSequence,
            'failedReleaseSequence': failedSequence,
            'failedManifestSha256': 'b' * 64,
            'knownGoodReleaseSequence': knownGoodSequence,
            'knownGoodManifestSha256': 'a' * 64,
            'releaseRequestId': 'prelaunch-$_rcManifestSha256',
            'approvedByRole': 'release-manager',
            'approvedAt': '2026-07-17T00:00:00.000Z',
            'reasonCode': 'PRELAUNCH_REHEARSAL',
          },
        );
        now = now.add(const Duration(seconds: 2));
        final rescueStopwatch = Stopwatch()..start();
        await updater.checkForUpdates();
        rescueStopwatch.stop();
        final rescuedPointer = await installer.readCurrentPointer();
        expect(rescuedPointer?.version, '18');
        expect(
          sha256.convert(await File(rescuedPointer!.path).readAsBytes()),
          sha256.convert(knownGoodSqliteBytes),
        );
        expect(
          (await stateRepository.readAcceptedManifestState(
            'production',
          ))?.releaseSequence,
          _rcReleaseSequence,
        );

        now = now.add(const Duration(seconds: 2));
        await updater.checkForUpdates();
        expect((await installer.readCurrentPointer())?.version, '18');

        manifestJson = _signedV2PackManifest(
          sequence: _rcReleaseSequence + 1,
          version: '20',
          compressedBytes: corruptBytes,
          sqliteBytes: const [5, 6, 7, 8],
        );
        now = now.add(const Duration(seconds: 2));
        final rejected = await updater.checkForUpdates();
        expect(rejected.single.status, DataPackInstallStatus.rejected);
        expect((await installer.readCurrentPointer())?.version, '18');

        manifestJson = _signedV2PackManifest(
          sequence: knownGoodSequence,
          version: '18',
          compressedBytes: knownGoodCompressedBytes,
          sqliteBytes: knownGoodSqliteBytes,
        );
        now = now.add(const Duration(seconds: 2));
        await expectLater(
          updater.checkForUpdates(trigger: UpdateTrigger.userConsent),
          throwsA(isA<DataPackClientException>()),
        );
        expect((await installer.readCurrentPointer())?.version, '18');
        debugPrint(
          jsonEncode({
            'artifactKind': 'android-datapack-monotonic-rescue-evidence',
            'status': 'PASS',
            'rcManifestSha256': computedManifestSha256,
            'rcArtifactSha256': computedArtifactSha256,
            'rescueReleaseSequence': _rcReleaseSequence,
            'rcManifestBytesVerified': true,
            'rcArtifactBytesVerified': true,
            'rcSignatureVerified': true,
            'rcSqliteIntegrityVerified': true,
            'knownGoodContentRestored': true,
            'idempotentReplayVerified': true,
            'corruptSuccessorPreservedKnownGood': true,
            'lowerSequenceRejected': true,
            'recoveryElapsedMs': rescueStopwatch.elapsedMilliseconds,
          }),
        );
      } finally {
        await server.close(force: true);
        await userDatabase.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

const _representativeRouteRegressions = [
  {
    'id': 'direct-local-capital',
    'pattern': 'DIRECT',
    'fromNodeId': 'station-a-line-1',
    'toNodeId': 'station-b-line-1',
    'requiredEdgeIds': ['edge-a-b'],
  },
  {
    'id': 'transfer-capital',
    'pattern': 'TRANSFER',
    'fromNodeId': 'station-a-line-1',
    'toNodeId': 'station-c-line-2',
    'requiredEdgeIds': ['edge-a-b', 'edge-b-transfer', 'edge-b-c'],
  },
  {
    'id': 'multi-transfer-capital',
    'pattern': 'MULTI_TRANSFER',
    'fromNodeId': 'station-a-line-1',
    'toNodeId': 'station-d-line-3',
    'requiredEdgeIds': [
      'edge-a-b',
      'edge-b-transfer',
      'edge-c-transfer',
      'edge-c-d',
    ],
  },
  {
    'id': 'loop-branch-capital',
    'pattern': 'LOOP_BRANCH',
    'fromNodeId': 'station-branch-line-2',
    'toNodeId': 'station-c-line-2',
    'requiredEdgeIds': ['edge-branch-loop', 'edge-loop-c'],
  },
  {
    'id': 'express-local-capital',
    'pattern': 'EXPRESS_LOCAL',
    'fromNodeId': 'station-a-line-1-express',
    'toNodeId': 'station-b-line-1-express',
    'requiredEdgeIds': ['edge-a-b-express'],
  },
];

Map<String, Object?> _packJson({
  required String version,
  required String url,
  required List<int> compressedBytes,
  required List<int> sqliteBytes,
}) {
  final compressedSha256 = sha256.convert(compressedBytes).toString();
  final sqliteSha256 = sha256.convert(sqliteBytes).toString();
  final sizeBytes = compressedBytes.length;
  return {
    'id': 'capital',
    'version': version,
    'url': url,
    'sha256': compressedSha256,
    'sqliteSha256': sqliteSha256,
    'sizeBytes': sizeBytes,
    'artifactKind': 'fixture',
    'representativeRouteRegressions': _representativeRouteRegressions,
    'representativeRouteRegressionSignature': {
      'algorithm': 'sha256-route-regression-v1',
      'value': sha256
          .convert(
            utf8.encode(
              'capital:$version:$compressedSha256:$sqliteSha256:$sizeBytes:${jsonEncode(_representativeRouteRegressions)}',
            ),
          )
          .toString(),
    },
    'signature': {
      'algorithm': 'sha256-pack-manifest-v2',
      'value': sha256
          .convert(
            utf8.encode(
              'capital:$version:$compressedSha256:$sqliteSha256:$sizeBytes',
            ),
          )
          .toString(),
    },
    'sourceInventory': const [
      {
        'id': 'fixture-capital-catalog',
        'owner': 'qa-role',
        'url': 'https://example.invalid/fixture',
        'license': 'fixture-only',
        'licenseStatus': 'fixture-only',
        'redistributionAllowed': false,
        'updateFrequency': 'manual',
        'updatedAt': '2026-07-17T00:00:00.000Z',
        'fields': ['stations'],
      },
    ],
    'regionalQualityMetrics': const {
      'stationCount': 2,
      'facilityCoverageRatio': 0.5,
      'edgeCount': 2,
      'unknownAccessibilityRatio': 0.0,
    },
    'schemaVersion': '1',
    'requiredTables': ['catalog_metadata'],
  };
}

Map<String, Object?> _signedV2PackManifest({
  required int sequence,
  required String version,
  required List<int> compressedBytes,
  required List<int> sqliteBytes,
  Map<String, Object?>? rollbackProvenance,
}) {
  final pack = _packJson(
    version: version,
    url: 'catalog/capital-v$version.sqlite.gz',
    compressedBytes: compressedBytes,
    sqliteBytes: sqliteBytes,
  );
  final body = <String, Object?>{
    'manifestVersion': 2,
    'channel': 'production',
    'releaseSequence': sequence,
    'publishedAt': '2026-07-17T00:00:00.000Z',
    'expiresAt': '2099-01-01T00:00:00.000Z',
    'keyId': 'fixture-key',
    'ttlSeconds': 1,
    'activePack': {'id': 'capital', 'version': version},
    'rollbackProvenance': ?rollbackProvenance,
    'packs': [pack],
  };
  final canonical = jsonEncode(_canonicalValue(body));
  return {
    ...body,
    'signature': {
      'algorithm': 'sha256-manifest-v2',
      'value': sha256.convert(utf8.encode(canonical)).toString(),
    },
  };
}

Object? _canonicalValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List<Object?>) {
    return value.map(_canonicalValue).toList(growable: false);
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _canonicalValue(value[key])};
  }
  throw ArgumentError('Unsupported canonical value: ${value.runtimeType}');
}

Future<List<int>> _catalogSqliteBytesWithMarker(
  Directory directory, {
  required String fileName,
  required String marker,
}) async {
  final file = File('${directory.path}/$fileName');
  final database = CatalogDatabase.file(file);
  await database.seedBaselineIfEmpty();
  await database.customStatement(
    'INSERT OR REPLACE INTO catalog_metadata(key, value) VALUES (?, ?)',
    ['rescueTestMarker', marker],
  );
  await database.close();
  return file.readAsBytes();
}
