class AppEndpoints {
  const AppEndpoints({
    required this.dataPackBaseUrl,
    required this.reportApiBaseUrl,
  });

  factory AppEndpoints.fromEnvironment() {
    return const AppEndpoints(
      dataPackBaseUrl: String.fromEnvironment(
        'EASYSUBWAY_DATA_PACK_BASE_URL',
        defaultValue: '',
      ),
      reportApiBaseUrl: String.fromEnvironment(
        'EASYSUBWAY_REPORT_API_BASE_URL',
        defaultValue: '',
      ),
    );
  }

  final String dataPackBaseUrl;
  final String reportApiBaseUrl;

  Uri? get dataPackManifestUri {
    final trimmed = dataPackBaseUrl.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final base = Uri.tryParse(trimmed);
    if (base == null || !base.hasScheme || base.host.isEmpty) {
      return null;
    }
    return base.resolve('catalog/current.json');
  }
}
