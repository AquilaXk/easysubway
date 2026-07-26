import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
// 정준 직렬화는 검증 대상 구현을 그대로 쓴다. 테스트가 규칙을 복제하면 3언어
// 분열(이슈 #2528)을 구조적으로 검출할 수 없다.
import 'package:easysubway_mobile/core/datapack/canonical_json.dart';
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
      final productionSigningPublicKey = DataPackSigningPublicKey(
        modulusBase64Url: publicKeyJson['modulusBase64Url']! as String,
        exponentBase64Url: publicKeyJson['exponentBase64Url']! as String,
        keyId: publicKeyJson['keyId']! as String,
      );
      final rcManifestJson =
          jsonDecode(utf8.decode(rcManifestBytes)) as Map<String, Object?>;
      final rcManifest = DataPackManifest.fromJson(
        rcManifestJson,
        productionSigningPublicKey: productionSigningPublicKey,
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
      final knownGoodManifestBytes = base64Decode(
        rcBundle['knownGoodManifestBytesBase64']! as String,
      );
      final failedManifestBytes = base64Decode(
        rcBundle['failedManifestBytesBase64']! as String,
      );
      final failedArtifactBytes = base64Decode(
        rcBundle['failedArtifactBytesBase64']! as String,
      );
      final knownGoodManifestJson =
          jsonDecode(utf8.decode(knownGoodManifestBytes))
              as Map<String, Object?>;
      final failedManifestJson =
          jsonDecode(utf8.decode(failedManifestBytes)) as Map<String, Object?>;
      final knownGoodManifest = DataPackManifest.fromJson(
        knownGoodManifestJson,
        productionSigningPublicKey: productionSigningPublicKey,
      );
      final failedManifest = DataPackManifest.fromJson(
        failedManifestJson,
        productionSigningPublicKey: productionSigningPublicKey,
      );
      final knownGoodPack = knownGoodManifest.packs.single;
      final failedPack = failedManifest.packs.single;
      expect(knownGoodManifest.releaseSequence, _rcReleaseSequence - 2);
      expect(failedManifest.releaseSequence, _rcReleaseSequence - 1);
      expect(knownGoodPack.compressedSha256, computedArtifactSha256);
      expect(
        sha256.convert(knownGoodManifestBytes).toString(),
        rcBundle['knownGoodManifestSha256'],
      );
      expect(
        sha256.convert(failedManifestBytes).toString(),
        rcBundle['failedManifestSha256'],
      );
      expect(
        sha256.convert(failedArtifactBytes).toString(),
        rcBundle['failedArtifactSha256'],
      );
      expect(failedPack.compressedSha256, rcBundle['failedArtifactSha256']);
      expect(
        failedPack.compressedSha256,
        isNot(knownGoodPack.compressedSha256),
      );
      expect(failedPack.sqliteSha256, isNot(knownGoodPack.sqliteSha256));
      final userDatabase = user_db.UserDatabase.memory();
      final catalogDirectory = Directory('${directory.path}/catalog');
      final corruptBytes = <int>[1, 2, 3, 4];
      var now = knownGoodManifest.publishedAt!.add(const Duration(seconds: 1));
      var manifestJson = knownGoodManifestJson;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        if (request.uri.path == '/datapacks/catalog/current.json') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(manifestJson))
            ..close();
        } else if (request.uri.path == knownGoodPack.url.path) {
          request.response
            ..statusCode = HttpStatus.ok
            ..add(rcArtifactBytes)
            ..close();
        } else if (request.uri.path == failedPack.url.path) {
          request.response
            ..statusCode = HttpStatus.ok
            ..add(failedArtifactBytes)
            ..close();
        } else if (request.uri.path ==
            '/datapacks/catalog/capital-v20.sqlite.gz') {
          request.response
            ..statusCode = HttpStatus.ok
            ..add(corruptBytes)
            ..close();
        } else {
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
      final manifestUri = Uri.parse(
        'http://${server.address.host}:${server.port}/datapacks/catalog/current.json',
      );
      final productionClient = DataPackClient(
        manifestUri: manifestUri,
        stateRepository: stateRepository,
        productionSigningPublicKey: productionSigningPublicKey,
        now: () => now,
      );
      final updater = DataPackUpdater(
        client: productionClient,
        installer: installer,
        httpClient: _LoopbackArtifactHttpClient(
          serverAddress: server.address,
          serverPort: server.port,
        ),
        now: () => now,
      );
      final fixtureUpdater = DataPackUpdater(
        client: DataPackClient(
          manifestUri: manifestUri,
          stateRepository: stateRepository,
          now: () => now,
        ),
        installer: installer,
        now: () => now,
      );

      try {
        await updater.checkForUpdates();
        expect(
          (await installer.readCurrentPointer())?.version,
          knownGoodPack.version,
        );
        manifestJson = failedManifestJson;
        now = now.add(const Duration(seconds: 3601));
        await updater.checkForUpdates();
        expect(
          (await installer.readCurrentPointer())?.version,
          failedPack.version,
        );

        manifestJson = rcManifestJson;
        now = now.add(const Duration(seconds: 3601));
        final rescueStopwatch = Stopwatch()..start();
        await updater.checkForUpdates();
        rescueStopwatch.stop();
        final rescuedPointer = await installer.readCurrentPointer();
        expect(rescuedPointer?.version, rcPack.version);
        expect(
          sha256.convert(await File(rescuedPointer!.path).readAsBytes()),
          sha256.convert(rcSqliteBytes),
        );
        expect(
          (await stateRepository.readAcceptedManifestState(
            'production',
          ))?.releaseSequence,
          _rcReleaseSequence,
        );

        now = now.add(const Duration(seconds: 3601));
        await updater.checkForUpdates();
        expect((await installer.readCurrentPointer())?.version, rcPack.version);

        manifestJson = _signedV2PackManifest(
          sequence: _rcReleaseSequence + 1,
          version: '20',
          compressedBytes: corruptBytes,
          sqliteBytes: const [5, 6, 7, 8],
        );
        now = now.add(const Duration(seconds: 3601));
        final rejected = await fixtureUpdater.checkForUpdates();
        expect(rejected.single.status, DataPackInstallStatus.rejected);
        expect((await installer.readCurrentPointer())?.version, rcPack.version);

        manifestJson = knownGoodManifestJson;
        now = now.add(const Duration(seconds: 3601));
        await expectLater(
          updater.checkForUpdates(trigger: UpdateTrigger.userConsent),
          throwsA(isA<DataPackClientException>()),
        );
        expect((await installer.readCurrentPointer())?.version, rcPack.version);
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
            'rcUpdaterReplayVerified': true,
            'knownGoodManifestSha256': sha256
                .convert(knownGoodManifestBytes)
                .toString(),
            'knownGoodArtifactSha256': knownGoodPack.compressedSha256,
            'failedManifestSha256': sha256
                .convert(failedManifestBytes)
                .toString(),
            'failedArtifactSha256': failedPack.compressedSha256,
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

class _LoopbackArtifactHttpClient implements HttpClient {
  _LoopbackArtifactHttpClient({
    required this.serverAddress,
    required this.serverPort,
  });

  final InternetAddress serverAddress;
  final int serverPort;
  final HttpClient _delegate = HttpClient();

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _delegate.getUrl(
    url.replace(scheme: 'http', host: serverAddress.host, port: serverPort),
  );

  @override
  void close({bool force = false}) => _delegate.close(force: force);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  final canonical = canonicalDataPackJson(body);
  return {
    ...body,
    'signature': {
      'algorithm': 'sha256-manifest-v2',
      'value': sha256.convert(utf8.encode(canonical)).toString(),
    },
  };
}
