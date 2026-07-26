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

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}
