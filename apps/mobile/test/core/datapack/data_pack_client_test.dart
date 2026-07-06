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
}
