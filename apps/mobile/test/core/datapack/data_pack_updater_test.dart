import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:easysubway_mobile/core/database/user/user_database.dart'
    as user_db;
import 'package:easysubway_mobile/core/datapack/data_pack_client.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_installer.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_update_state.dart';
import 'package:easysubway_mobile/core/datapack/data_pack_updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('updater는 서버가 손상 pack을 내려주면 기존 current를 유지한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'easysubway-datapack-updater-corrupt-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final userDatabase = user_db.UserDatabase.memory();
    addTearDown(userDatabase.close);
    final catalogDirectory = Directory('${directory.path}/catalog');
    await catalogDirectory.create(recursive: true);
    final oldPack = File('${catalogDirectory.path}/capital-v17.sqlite');
    await oldPack.writeAsString('old pack');
    await File('${catalogDirectory.path}/current.json').writeAsString(
      jsonEncode({
        'id': 'capital',
        'version': '17',
        'path': oldPack.path,
        'sha256': 'old-sha',
      }),
    );
    final corruptBytes = [1, 2, 3, 4];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) {
      if (request.uri.path == '/manifest.json') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'ttlSeconds': 60,
              'packs': [
                {
                  'id': 'capital',
                  'version': '18',
                  'url': 'capital-v18.sqlite.gz',
                  'sha256': sha256.convert(corruptBytes).toString(),
                  'sqliteSha256': '1' * 64,
                  'schemaVersion': '1',
                  'requiredTables': ['catalog_metadata'],
                },
              ],
            }),
          )
          ..close();
        return;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..add(corruptBytes)
        ..close();
    });
    final stateRepository = DataPackUpdateStateRepository(
      userDatabase: userDatabase,
      now: () => DateTime.utc(2026, 6, 19, 10),
    );
    final installer = DataPackInstaller(
      catalogDirectory: catalogDirectory,
      userDatabase: userDatabase,
    );
    final updater = DataPackUpdater(
      client: DataPackClient(
        manifestUri: Uri.parse(
          'http://${server.address.host}:${server.port}/manifest.json',
        ),
        stateRepository: stateRepository,
      ),
      installer: installer,
    );

    final results = await updater.checkForUpdates();
    final pointer = await installer.readCurrentPointer();

    expect(results.single.status, DataPackInstallStatus.rejected);
    expect(results.single.reason, DataPackInstallRejectionReason.invalidArchive);
    expect(pointer?.version, '17');
    expect(await oldPack.exists(), isTrue);
  });
}
