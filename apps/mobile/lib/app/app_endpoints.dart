class AppEndpoints {
  const AppEndpoints({
    required this.dataPackBaseUrl,
    required this.dataPackSigningKey,
    required this.reportApiBaseUrl,
  });

  factory AppEndpoints.fromEnvironment() {
    return const AppEndpoints(
      dataPackBaseUrl: String.fromEnvironment(
        'EASYSUBWAY_DATA_PACK_BASE_URL',
        defaultValue: '',
      ),
      dataPackSigningKey: String.fromEnvironment(
        'EASYSUBWAY_DATAPACK_SIGNING_KEY',
        defaultValue: '',
      ),
      reportApiBaseUrl: String.fromEnvironment(
        'EASYSUBWAY_REPORT_API_BASE_URL',
        defaultValue: '',
      ),
    );
  }

  final String dataPackBaseUrl;
  final String dataPackSigningKey;
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

  String? get productionDataPackSigningKey {
    final trimmed = dataPackSigningKey.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
