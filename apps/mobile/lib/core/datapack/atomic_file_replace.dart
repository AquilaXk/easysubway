import 'dart:io';

/// 교체 도중 옆으로 옮겨 둔 직전 파일에 붙이는 접미사(#2532).
///
/// 팩 파일(`*.sqlite`)·pointer(`current.json`)와 확장자가 달라야 한다. 설치 팩 정리
/// (`data_pack_installer.dart`)와 known-good 탐색(`catalog_database_opener.dart`)이
/// `.sqlite`로 끝나는 이름만 훑으므로 이 접미사가 붙은 파일은 어느 쪽에도 잡히지 않는다.
const _replacedTargetSuffix = '.previous';

/// [target]을 교체하는 동안 직전 내용을 담아 두는 파일.
File replacedTargetBackupFile(File target) {
  return File('${target.path}$_replacedTargetSuffix');
}

/// [temporary]를 [target] 자리로 옮긴다(#2532).
///
/// rename 한 번으로 끝나는 것이 정상 경로다. rename이 실패했을 때 **대상을 지우고 다시
/// 시도하지 않는다** — 지운 직후 중단되면 되돌릴 수 없어 pointer나 활성 팩이 통째로
/// 사라지고, 열기 경로가 이유 없이 번들 팩으로 강등된다. 대신 대상을 [replacedTargetBackupFile]
/// 이름으로 옮겨 두고 교체를 다시 시도하며, 그마저 실패하면 옮겨 둔 파일을 제자리로 되돌린 뒤
/// 예외를 그대로 올린다. 교체가 끝나면 옮겨 둔 파일을 지운다.
///
/// 두 번째 rename과 정리 사이에서 중단되면 대상과 직전 파일이 함께 남는다.
/// [restoreReplacedTarget]이 그 잔재를 정리하고, 대상만 없는 경우에는 직전 파일을 되살린다.
Future<void> replaceFileAtomically({
  required File temporary,
  required File target,
}) async {
  try {
    await temporary.rename(target.path);
    return;
  } on FileSystemException {
    // 폴백으로 내려간다. 대상은 이 시점에도 그대로 남아 있다.
  }

  if (!await temporary.exists()) {
    // 원본이 사라져 실패한 교체는 대상을 옆으로 옮겨도 결과가 같다. 옮겼다 되돌리는
    // 동안 대상이 잠깐 사라지는 창만 생기고, 그 창에서 pointer를 읽는 다른 isolate는
    // 설치 팩 없음으로 판정해 강등된다. 대상을 건드리지 않고 바로 올린다.
    throw FileSystemException('Missing replacement source.', temporary.path);
  }

  final backup = replacedTargetBackupFile(target);
  await _deleteIfExists(backup);
  final movedAside = await target.exists();
  if (movedAside) {
    await target.rename(backup.path);
  }
  try {
    await temporary.rename(target.path);
  } on FileSystemException {
    if (movedAside) {
      await backup.rename(target.path);
    }
    rethrow;
  }
  if (movedAside) {
    await _deleteIfExists(backup);
  }
}

/// 교체가 중단돼 남은 [replacedTargetBackupFile]을 정리한다(#2532).
///
/// 대상이 없으면 직전 파일을 제자리로 되돌리고, 대상이 이미 있으면 잔재만 지운다.
/// 대상을 여는 경로에서 읽기 직전에 호출한다.
Future<void> restoreReplacedTarget(File target) async {
  final backup = replacedTargetBackupFile(target);
  if (!await backup.exists()) {
    return;
  }
  if (await target.exists()) {
    await _deleteIfExists(backup);
    return;
  }
  await backup.rename(target.path);
}

/// [directory]에 남은 모든 교체 잔재를 정리한다(#2532).
///
/// 교체 대상은 pointer(`current.json`)만이 아니라 설치 팩(`<id>-v<n>.sqlite`),
/// 무결성 기준선(`<pack>.sqlite.sha256`), 번들 팩, freshness 파일까지다. 이름별로 복구
/// 호출을 흩어 두면 어느 하나가 빠졌을 때 잔재가 영구히 남거나(정리 필터가 `.sqlite`만
/// 본다) 기준선이 유실된 채 재활성화가 영구 거부된다. 디렉토리 단위로 한 번에 훑어
/// 대상이 없으면 되살리고, 있으면 잔재를 지운다.
Future<void> restoreInterruptedReplacements(Directory directory) async {
  if (!await directory.exists()) {
    return;
  }
  final backups = await directory
      .list()
      .where((entity) => entity is File)
      .cast<File>()
      .where((file) => file.path.endsWith(_replacedTargetSuffix))
      .toList();
  for (final backup in backups) {
    final targetPath = backup.path.substring(
      0,
      backup.path.length - _replacedTargetSuffix.length,
    );
    await restoreReplacedTarget(File(targetPath));
  }
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}
