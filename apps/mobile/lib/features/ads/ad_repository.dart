import '../../core/network/api_client.dart';

enum AdPlacement {
  routeResultBottom('route-result-bottom'),
  stationDetailBottom('station-detail-bottom');

  const AdPlacement(this.id);

  final String id;
}

final class AdCreative {
  const AdCreative({
    required this.placement,
    required this.creativeId,
    required this.imageUrl,
    required this.landingUrl,
    required this.advertiserName,
    required this.altText,
  });

  final AdPlacement placement;
  final String creativeId;
  final Uri imageUrl;
  final Uri landingUrl;
  final String advertiserName;
  final String altText;
}

final class AdRepository {
  const AdRepository(ApiClient apiClient)
    : _apiClient = apiClient,
      _baseUri = null;

  const AdRepository.lazy(Uri? Function() baseUri)
    : _apiClient = null,
      _baseUri = baseUri;

  final ApiClient? _apiClient;
  final Uri? Function()? _baseUri;

  /// ponytail: 현재 200 응답만 사용한다. 캐시와 event 전송은 Phase A 범위 밖이다.
  Future<AdCreative?> fetchActive(AdPlacement placement) async {
    final apiClient = _apiClient;
    final resolvedClient = apiClient ?? _lazyClient();
    if (resolvedClient == null) {
      return null;
    }
    final ApiResponse response;
    try {
      response = await resolvedClient.getJson(
        '/api/ads/active?placement=${placement.id}',
      );
    } on ApiException {
      return null;
    }

    if (!response.isOk) {
      return null;
    }
    final body = response.jsonBody;
    if (body is! Map<String, Object?> || body['success'] != true) {
      return null;
    }
    final data = body['data'];
    if (data is! Map<String, Object?>) {
      return null;
    }

    final responsePlacement = _text(data, 'placement');
    final creativeId = _text(data, 'creativeId');
    final imageUrl = _httpsUri(_text(data, 'imageUrl'));
    final landingUrl = _httpsUri(_text(data, 'landingUrl'));
    final advertiserName = _text(data, 'advertiserName');
    final altText = _text(data, 'altText');
    if (responsePlacement != placement.id ||
        creativeId == null ||
        imageUrl == null ||
        landingUrl == null ||
        advertiserName == null ||
        altText == null) {
      return null;
    }

    return AdCreative(
      placement: placement,
      creativeId: creativeId,
      imageUrl: imageUrl,
      landingUrl: landingUrl,
      advertiserName: advertiserName,
      altText: altText,
    );
  }

  ApiClient? _lazyClient() {
    final baseUri = _baseUri!();
    return baseUri == null ? null : ApiClient(baseUri: baseUri);
  }
}

String? _text(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

Uri? _httpsUri(String? value) {
  if (value == null) {
    return null;
  }
  final uri = Uri.tryParse(value);
  return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
      ? uri
      : null;
}
