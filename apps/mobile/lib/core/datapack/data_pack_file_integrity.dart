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
  final output = _DigestSink();
  final input = sha256.startChunkedConversion(output);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return output.value.toString();
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
Future<void> writeInstalledPackBaseline(
  File packFile,
  String sha256Value,
) async {
  final baseline = installedPackBaselineFile(packFile);
  final temporary = File('${baseline.path}.installing');
  await temporary.writeAsString('$sha256Value\n', flush: true);
  await replaceFileAtomically(temporary: temporary, target: baseline);
}

/// 기록된 기대 해시. 기준선이 없거나 형식이 깨졌으면 `null`.
Future<String?> readInstalledPackBaseline(File packFile) async {
  final baseline = installedPackBaselineFile(packFile);
  if (!await baseline.exists()) {
    return null;
  }
  final value = (await baseline.readAsString()).trim();
  return isSha256Text(value) ? value : null;
}

/// 설치 팩과 함께 기준선 파일도 지운다.
Future<void> deleteInstalledPackBaseline(File packFile) async {
  final baseline = installedPackBaselineFile(packFile);
  if (await baseline.exists()) {
    await baseline.delete();
  }
}

bool isSha256Text(String value) {
  return RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
}

class _DigestSink implements Sink<Digest> {
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
