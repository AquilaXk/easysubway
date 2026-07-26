import 'dart:io';

import 'package:easysubway_mobile/core/datapack/atomic_file_replace.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('교체는 임시 파일을 대상 자리로 옮기고 임시 파일을 남기지 않는다', () async {
    final directory = await _temporaryDirectory('replace-happy-');
    final target = File('${directory.path}/current.json');
    await target.writeAsString('previous');
    final temporary = File('${target.path}.installing');
    await temporary.writeAsString('next');

    await replaceFileAtomically(temporary: temporary, target: target);

    expect(await target.readAsString(), 'next');
    expect(await temporary.exists(), isFalse);
    expect(await replacedTargetBackupFile(target).exists(), isFalse);
  });

  test('rename이 실패해도 대상 파일과 내용이 그대로 남는다', () async {
    // 임시 파일이 이미 사라진 상태에서 rename이 실패하는 상황(#2532).
    // delete-후-rename 폴백은 이 경로에서 대상 파일을 먼저 지워 되돌릴 수 없었다.
    final directory = await _temporaryDirectory('replace-preserve-');
    final target = File('${directory.path}/current.json');
    await target.writeAsString('previous');
    final temporary = File('${target.path}.installing');

    await expectLater(
      replaceFileAtomically(temporary: temporary, target: target),
      throwsA(isA<FileSystemException>()),
    );

    expect(await target.exists(), isTrue);
    expect(await target.readAsString(), 'previous');
    expect(await replacedTargetBackupFile(target).exists(), isFalse);
  });

  test('교체 중단으로 대상이 없고 직전 파일만 남으면 되돌린다', () async {
    final directory = await _temporaryDirectory('replace-restore-');
    final target = File('${directory.path}/current.json');
    await replacedTargetBackupFile(target).writeAsString('previous');

    await restoreReplacedTarget(target);

    expect(await target.readAsString(), 'previous');
    expect(await replacedTargetBackupFile(target).exists(), isFalse);
  });

  test('대상과 직전 파일이 함께 남아 있으면 직전 파일만 지운다', () async {
    final directory = await _temporaryDirectory('replace-stale-');
    final target = File('${directory.path}/current.json');
    await target.writeAsString('next');
    await replacedTargetBackupFile(target).writeAsString('previous');

    await restoreReplacedTarget(target);

    expect(await target.readAsString(), 'next');
    expect(await replacedTargetBackupFile(target).exists(), isFalse);
  });
}

Future<Directory> _temporaryDirectory(String prefix) async {
  final directory = await Directory.systemTemp.createTemp(
    'easysubway-datapack-$prefix',
  );
  addTearDown(() => directory.delete(recursive: true));
  return directory;
}
