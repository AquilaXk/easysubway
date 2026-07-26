import 'dart:io';

import 'package:crypto/crypto.dart';

import 'atomic_file_replace.dart';

/// 설치 팩 파일의 기대 해시를 담는 기준선 파일 접미사(#2532).
const _baselineSuffix = '.sha256';

/// 파일 전체를 스트리밍해 sha256을 계산한다(#2532).
///
/// 설치 검증·journal 복구·재활성화 대조가 모두 이 한 함수를 쓴다. 같은 판정을 두 방식으로
/// 구현하면 규칙이 갈라지고, 큰 팩을 통째로 메모리에 올리는 경로가 섞인다.
Future<String> sha256OfFile(File file) async {
  final output = Sha256DigestSink();
  final input = sha256.startChunkedConversion(output);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return output.value.toString();
}

/// 청크 스트림의 sha256 결과를 받는 sink. 스트리밍 해시를 쓰는 경로가 공유한다.
class Sha256DigestSink implements Sink<Digest> {
  Digest? _value;

  Digest get value {
    final digest = _value;
    if (digest == null) {
      throw const FormatException('Missing digest.');
    }
    return digest;
  }

  @override
  void add(Digest data) {
    _value = data;
  }

  @override
  void close() {}
}

/// 설치 팩 파일과 짝을 이루는 기준선 파일.
File installedPackBaselineFile(File packFile) {
  return File('${packFile.path}$_baselineSuffix');
}

/// 설치 팩의 기대 해시를 기록한다(#2532).
///
/// 버전별 파일과 1:1로 두는 이유: `installed_data_packs` 레코드는 pack id가 기본키라
/// 같은 pack의 이전 버전 기대 해시를 보관하지 못하고, pointer는 활성 버전 하나만 담는다.
/// 롤백처럼 **이미 설치된 이전 버전을 다시 가리키는** 경로에는 그 둘 다 기준선을 주지 못한다.
///
/// 방어 범위: 이 파일은 팩 파일과 같은 디렉토리의 평문이라 **신뢰 루트가 아니다.** 팩 파일을
/// 바꿀 수 있는 주체는 기준선도 함께 바꿀 수 있다. 이 대조가 닫는 것은 우발적 손상·부분
/// 기록·앱이 모르는 사이의 파일 교체이고, 같은 권한을 가진 능동적 변조를 막는 것은 서명된
/// 매니페스트 값(대조 사다리 1단)뿐이다.
Future<void> writeInstalledPackBaseline(
  File packFile,
  String sha256Value,
) async {
  final baseline = installedPackBaselineFile(packFile);
  // 앱과 홈 위젯 isolate가 같은 팩을 동시에 열 수 있다. 임시 이름이 고정이면 두 쪽이 같은
  // 파일에 쓰고 rename을 겨뤄, 늦은 쪽이 기준선을 옆으로 옮긴 창에서 중단될 수 있다.
  final temporary = File('${baseline.path}.$pid.installing');
  try {
    await temporary.writeAsString('$sha256Value\n', flush: true);
    await replaceFileAtomically(temporary: temporary, target: baseline);
  } finally {
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
}

/// 기록된 기대 해시. 기준선이 없거나 형식이 깨졌으면 `null`.
Future<String?> readInstalledPackBaseline(File packFile) async {
  final baseline = installedPackBaselineFile(packFile);
  // 교체가 중단돼 직전 기준선만 남았으면 되살린다. 기준선이 유실되면 그 버전은 대조할
  // 기준이 없어 재활성화가 영구히 거부된다.
  await restoreReplacedTarget(baseline);
  if (!await baseline.exists()) {
    return null;
  }
  return normalizedSha256Text(await baseline.readAsString());
}

/// 설치 팩과 함께 기준선 파일도 지운다. 교체 잔재(`.previous`)도 같이 지운다.
Future<void> deleteInstalledPackBaseline(File packFile) async {
  final baseline = installedPackBaselineFile(packFile);
  await _deleteIfExists(baseline);
  await _deleteIfExists(replacedTargetBackupFile(baseline));
}

/// 해시 문자열을 대조에 쓸 수 있는 형태로 정규화한다. 형식이 아니면 `null`.
///
/// 대소문자를 함께 정규화하는 이유: 사다리 3·4단(pointer·설치 레코드)은 과거 빌드가 쓴
/// 값이라 대문자 hex일 수 있고, 그대로 두면 정상 값이 한쪽에서만 탈락한다.
String? normalizedSha256Text(String? value) {
  final normalized = value?.trim().toLowerCase();
  if (normalized == null || !isSha256Text(normalized)) {
    return null;
  }
  return normalized;
}

bool isSha256Text(String value) {
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}
