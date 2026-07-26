import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/data_pack_client.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manifest 요청은 Cache-Control: no-cache 헤더를 포함한다', () async {
    final capturedCacheControl = <String?>[];

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      if (request.uri.path == '/manifest.json') {
        capturedCacheControl.add(
          request.headers.value(HttpHeaders.cacheControlHeader),
        );
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'ttlSeconds': 60, 'packs': <Object?>[]}))
          ..close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.notFound
        ..close();
    });

    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 7, 6, 10),
    );
    final client = DataPackClient(
      manifestUri: Uri.parse(
        'http://${server.address.host}:${server.port}/manifest.json',
      ),
      stateRepository: stateRepository,
      now: () => DateTime.utc(2026, 7, 6, 10),
    );

    await client.fetchManifestIfNeeded();

    expect(capturedCacheControl, hasLength(1));
    expect(capturedCacheControl.single, 'no-cache');
  });

  // 이슈 #2528: jsonEncode의 JsonUnsupportedObjectError는 Error라서 fetchManifest의
  // `on FormatException` 핸들러를 우회하고 app_bootstrap의 광역 catch까지 새어 나갔다.
  // 정준화가 FormatException으로 정규화하면 여기서 DataPackClientException이 된다.
  test('유한하지 않은 숫자가 든 매니페스트는 DataPackClientException으로 분류된다', () async {
    const body =
        '{"manifestVersion":2,"ttlSeconds":60,"packs":[],"keyId":"production-v1",'
        '"overflow":1e400,'
        '"signature":{"algorithm":"sha256-manifest-v2","value":"deadbeef"}}';

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(body)
        ..close();
    });

    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final client = DataPackClient(
      manifestUri: Uri.parse(
        'http://${server.address.host}:${server.port}/manifest.json',
      ),
      stateRepository: DataPackUpdateStateRepository(
        userDatabase: userDatabase,
        now: () => DateTime.utc(2026, 7, 6, 10),
      ),
      now: () => DateTime.utc(2026, 7, 6, 10),
    );

    await expectLater(
      client.fetchManifestIfNeeded(),
      throwsA(isA<DataPackClientException>()),
    );
  });
}
