import '../core/datapack/data_pack_manifest.dart';

/// production 채널 매니페스트 수락 절대 순번 하한(이슈 #2531).
///
/// 값의 단일 원본은 `apps/mobile/release/datapack-manifest-acceptance-policy.json`이고
/// 두 값이 어긋나면
/// `apps/mobile/test/core/datapack/data_pack_manifest_acceptance_policy_test.dart`가
/// 실패한다. 하한을 올리려면 그 정책 파일에 새 관측값을 기록해야 하며, 데이터팩 릴리즈
/// workflow가 publish 직전 `releaseSequence >= minimumReleaseSequence`를 검사한다.
const int productionDataPackMinimumReleaseSequence = 114;

/// 데이터팩 서명 공개키 dart-define의 주입 상태(이슈 #2532).
enum DataPackSigningPublicKeyStatus {
  /// modulus 또는 exponent가 비어 있다.
  missing,

  /// 값은 있지만 RSA 공개키 형식이 아니다.
  malformed,

  /// 서명 검증에 쓸 수 있는 형식이다.
  present,
}

/// 데이터팩 업데이트 시작 판정(이슈 #2532).
enum DataPackUpdateStartDecision {
  /// 업데이트를 시작한다.
  start,

  /// 데이터팩 base URL이 없어 확인할 카탈로그가 없다(개발·테스트 빌드).
  noManifestEndpoint,

  /// production 빌드인데 서명 공개키가 주입되지 않았다.
  missingProductionSigningKey,

  /// production 빌드인데 서명 공개키 형식이 RSA 공개키가 아니다.
  malformedProductionSigningKey,
}

extension DataPackUpdateStartDecisionDiagnostics
    on DataPackUpdateStartDecision {
  /// 업데이트를 시작하지 않은 이유. 진단 신호가 필요한 경우에만 값이 있다.
  ///
  /// base URL이 없는 구성은 개발·테스트 빌드의 정상 상태라 신호를 남기지 않는다.
  String? get blockedDiagnosticMessage => switch (this) {
    DataPackUpdateStartDecision.start ||
    DataPackUpdateStartDecision.noManifestEndpoint => null,
    DataPackUpdateStartDecision.missingProductionSigningKey =>
      'production 빌드에 이동 정보 서명 공개키가 주입되지 않아 업데이트를 시작하지 않았습니다.',
    DataPackUpdateStartDecision.malformedProductionSigningKey =>
      'production 빌드의 이동 정보 서명 공개키 형식이 올바르지 않아 업데이트를 시작하지 않았습니다.',
  };
}

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

  /// 서명 공개키 dart-define의 주입 상태(이슈 #2532).
  ///
  /// [productionDataPackSigningPublicKey]는 미주입이면 `null`, 형식이 깨졌으면 검증에서만
  /// 실패하는 키 객체를 돌려주므로 호출자가 둘을 구분할 수 없었다. 형식 오류는 매 시도마다
  /// 서명 검증 실패로 끝나 네트워크·파싱 실패와 섞여 보이므로 별도로 구분한다.
  DataPackSigningPublicKeyStatus get dataPackSigningPublicKeyStatus {
    final key = productionDataPackSigningPublicKey;
    if (key == null) {
      return DataPackSigningPublicKeyStatus.missing;
    }
    return key.hasSupportedRsaFormat
        ? DataPackSigningPublicKeyStatus.present
        : DataPackSigningPublicKeyStatus.malformed;
  }

  /// 이 빌드가 스스로 production 채널이라고 선언했는지(이슈 #2532).
  ///
  /// [expectedDataPackChannel]과 기준이 다르다. 그쪽은 "이 빌드가 어떤 채널의 카탈로그를
  /// 기대하는가"라 값이 비면 production으로 정규화하지만(수락 판정의 기본값), 이 술어는
  /// "빌드가 production이라고 선언했는가"이므로 빈 값을 production으로 보지 않는다.
  ///
  /// 두 기준을 하나로 합치면 `.env.example` 구성(base URL은 로컬 서버, 채널·서명 공개키는
  /// 빈 값)의 개발·QA 빌드가 [dataPackUpdateStartDecision]에서 전부 차단된다.
  /// `contracts/env/env-scope-map.json`도 `EASYSUBWAY_DATAPACK_CHANNEL`을
  /// `datapack-release` scope로만 선언해 모바일 빌드 입력이 아니다. 스토어 경로는
  /// `tools/ci/validate-store-privacy-env.mjs`가 채널을 `production`으로 강제하므로
  /// 이 술어로도 닫힌 상태가 유지된다.
  bool get declaresProductionDataPackChannel {
    return dataPackChannel.trim() == 'production';
  }

  /// 이 빌드가 데이터팩 업데이트를 시작해도 되는지(이슈 #2532).
  ///
  /// production 빌드 판정은 [declaresProductionDataPackChannel]을 쓴다. DP-05(#2531)가
  /// 수락 순번 하한에 쓴 채널 조건과 같은 dart-define을 보되, 빈 값을 production으로
  /// 승격하지 않는 점만 다르다(위 술어 주석 참고).
  ///
  /// 서명 공개키가 없거나 형식이 깨진 production 빌드는 봉투 서명이 자기해시 대조로
  /// 강등돼 발신자 인증이 사라지므로 업데이트를 아예 시작하지 않는다. 채널을 production으로
  /// 선언하지 않은 개발·테스트 빌드는 기존 자기해시 폴백을 그대로 쓴다.
  DataPackUpdateStartDecision get dataPackUpdateStartDecision {
    if (dataPackManifestUri == null) {
      return DataPackUpdateStartDecision.noManifestEndpoint;
    }
    if (!declaresProductionDataPackChannel) {
      return DataPackUpdateStartDecision.start;
    }
    return switch (dataPackSigningPublicKeyStatus) {
      DataPackSigningPublicKeyStatus.missing =>
        DataPackUpdateStartDecision.missingProductionSigningKey,
      DataPackSigningPublicKeyStatus.malformed =>
        DataPackUpdateStartDecision.malformedProductionSigningKey,
      DataPackSigningPublicKeyStatus.present =>
        DataPackUpdateStartDecision.start,
    };
  }

  /// 이 빌드에 적용되는 매니페스트 수락 순번 하한. 정책 파일이 선언한 적용 범위와
  /// 같은 조건 — production 서명 공개키가 주입되고 기대 채널이 production인 빌드 —
  /// 에서만 값이 있고, 개발·테스트 빌드에서는 null이라 기존 동작이 유지된다.
  ///
  /// 채널 조건이 필요한 이유: `EASYSUBWAY_DATAPACK_CHANNEL`은 서명 공개키와 독립된
  /// dart-define이라, 키를 주입하면서 채널만 다르게 준 빌드는 순번 계열이 다른 카탈로그에
  /// production 하한을 적용하게 된다.
  int? get dataPackMinimumReleaseSequence {
    if (productionDataPackSigningPublicKey == null ||
        expectedDataPackChannel != 'production') {
      return null;
    }
    return productionDataPackMinimumReleaseSequence;
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
