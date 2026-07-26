import '../core/datapack/data_pack_manifest.dart';

/// production 채널 매니페스트 수락 절대 순번 하한(이슈 #2531).
///
/// 값의 단일 원본은 `apps/mobile/release/datapack-manifest-acceptance-policy.json`이고
/// 두 값이 어긋나면
/// `apps/mobile/test/core/datapack/data_pack_manifest_acceptance_policy_test.dart`가
/// 실패한다. 하한을 올리려면 그 정책 파일에 새 관측값을 기록해야 하며, 데이터팩 릴리즈
/// workflow가 publish 직전 `releaseSequence >= minimumReleaseSequence`를 검사한다.
const int productionDataPackMinimumReleaseSequence = 114;

class AppEndpoints {
  const AppEndpoints({
    required this.dataPackBaseUrl,
    required this.dataPackSigningPublicKeyModulus,
    required this.dataPackSigningPublicKeyExponent,
    required this.reportApiBaseUrl,
    this.dataPackSigningKeyId = 'production-v1',
    this.dataPackChannel = 'production',
  });

  factory AppEndpoints.fromEnvironment() {
    return const AppEndpoints(
      dataPackBaseUrl: String.fromEnvironment(
        'EASYSUBWAY_DATA_PACK_BASE_URL',
        defaultValue: '',
      ),
      dataPackSigningPublicKeyModulus: String.fromEnvironment(
        'EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_N',
        defaultValue: '',
      ),
      dataPackSigningPublicKeyExponent: String.fromEnvironment(
        'EASYSUBWAY_DATAPACK_SIGNING_PUBLIC_KEY_E',
        defaultValue: '',
      ),
      dataPackSigningKeyId: String.fromEnvironment(
        'EASYSUBWAY_DATAPACK_SIGNING_KEY_ID',
        defaultValue: 'production-v1',
      ),
      dataPackChannel: String.fromEnvironment(
        'EASYSUBWAY_DATAPACK_CHANNEL',
        defaultValue: 'production',
      ),
      reportApiBaseUrl: String.fromEnvironment(
        'EASYSUBWAY_REPORT_API_BASE_URL',
        defaultValue: '',
      ),
    );
  }

  final String dataPackBaseUrl;
  final String dataPackSigningPublicKeyModulus;
  final String dataPackSigningPublicKeyExponent;
  final String dataPackSigningKeyId;
  final String dataPackChannel;
  final String reportApiBaseUrl;

  Uri? get dataPackManifestUri {
    final trimmed = dataPackBaseUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final normalized = trimmed.endsWith('/') ? trimmed : '$trimmed/';
    final base = Uri.tryParse(normalized);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      return null;
    }
    return base.resolve('catalog/current.json');
  }

  DataPackSigningPublicKey? get productionDataPackSigningPublicKey {
    final modulus = dataPackSigningPublicKeyModulus.trim();
    final exponent = dataPackSigningPublicKeyExponent.trim();
    if (modulus.isEmpty || exponent.isEmpty) {
      return null;
    }
    return DataPackSigningPublicKey(
      modulusBase64Url: modulus,
      exponentBase64Url: exponent,
      keyId: dataPackSigningKeyId.trim().isEmpty
          ? 'production-v1'
          : dataPackSigningKeyId.trim(),
    );
  }

  /// 이 빌드에 적용되는 매니페스트 수락 순번 하한. production 서명 공개키가 주입된
  /// 빌드에서만 값이 있고, 개발·테스트 빌드에서는 null이라 기존 동작이 유지된다.
  int? get dataPackMinimumReleaseSequence {
    return productionDataPackSigningPublicKey == null
        ? null
        : productionDataPackMinimumReleaseSequence;
  }

  String get expectedDataPackChannel {
    final trimmed = dataPackChannel.trim();
    return trimmed.isEmpty ? 'production' : trimmed;
  }

  Uri? get realtimeApiBaseUri {
    final trimmed = reportApiBaseUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final base = Uri.tryParse(trimmed.endsWith('/') ? trimmed : '$trimmed/');
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      return null;
    }
    return base;
  }
}
