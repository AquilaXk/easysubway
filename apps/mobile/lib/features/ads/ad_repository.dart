import '../../core/network/api_client.dart';

enum AdPlacement {
  routeResultBottom('route-result-bottom'),
  stationDetailBottom('station-detail-bottom');

  const AdPlacement(this.id);

  final String id;
}

enum AdEventType {
  impression('IMPRESSION'),
  click('CLICK');

  const AdEventType(this.wireValue);
  final String wireValue;
}

final class AdCreative {
  const AdCreative({
    required this.placement,
    required this.creativeId,
    required this.imageUrl,
    required this.landingUrl,
    required this.advertiserName,
    required this.altText,
    required this.endsAt,
  });

  final AdPlacement placement;
  final String creativeId;
  final Uri imageUrl;
  final Uri landingUrl;
  final String advertiserName;
  final String altText;
  final DateTime? endsAt;
}

final class AdRepository {
  AdRepository(ApiClient apiClient) : _apiClient = apiClient, _baseUri = null;

  AdRepository.lazy(Uri? Function() baseUri)
    : _apiClient = null,
      _baseUri = baseUri;

  ApiClient? _apiClient;
  final Uri? Function()? _baseUri;

  /// ponytail: 현재 200 응답만 사용한다. 소재 캐시와 event 저장/재시도는 범위 밖이다.
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
    if (!data.containsKey('endsAt')) {
      return null;
    }
    final endsAtValue = data['endsAt'];
    final endsAt = _utcDateTime(endsAtValue);
    if (endsAtValue != null && endsAt == null) {
      return null;
    }
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
      endsAt: endsAt,
    );
  }

  Future<void> recordEvent(
    AdPlacement placement,
    String creativeId,
    AdEventType eventType,
  ) async {
    final resolvedClient = _apiClient ?? _lazyClient();
    if (resolvedClient == null) {
      return;
    }
    try {
      await resolvedClient.postJson(
        '/api/ads/events',
        body: {
          'placement': placement.id,
          'creativeId': creativeId,
          'eventType': eventType.wireValue,
        },
      );
    } on ApiException {
      return;
    }
  }

  ApiClient? _lazyClient() {
    final baseUri = _baseUri!();
    return baseUri == null ? null : _apiClient = ApiClient(baseUri: baseUri);
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

DateTime? _utcDateTime(Object? value) {
  if (value is! String) {
    return null;
  }
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !parsed.isUtc ||
      parsed.year != int.parse(match[1]!) ||
      parsed.month != int.parse(match[2]!) ||
      parsed.day != int.parse(match[3]!) ||
      parsed.hour != int.parse(match[4]!) ||
      parsed.minute != int.parse(match[5]!) ||
      parsed.second != int.parse(match[6]!)) {
    return null;
  }
  return parsed;
}
