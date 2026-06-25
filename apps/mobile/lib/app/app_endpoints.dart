import '../core/datapack/data_pack_manifest.dart';

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

  String get expectedDataPackChannel {
    final trimmed = dataPackChannel.trim();
    return trimmed.isEmpty ? 'production' : trimmed;
  }
}
