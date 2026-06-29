import 'dart:io';

import '../../core/network/api_client.dart';
import '../../mobile_error_reporter.dart';

enum RealtimeSnapshotStatus { loading, fresh, stale, unsupported, unavailable }

class RealtimeStationQuery {
  const RealtimeStationQuery({
    required this.stationId,
    required this.lineId,
    required this.stationQueryName,
    this.providerLineId,
  });

  final String stationId;
  final String lineId;
  final String stationQueryName;
  final String? providerLineId;
}

class RealtimeArrival {
  const RealtimeArrival({
    required this.lineId,
    required this.stationName,
    required this.destination,
    required this.direction,
    required this.trainNo,
    required this.message,
    this.etaSeconds,
    this.positionMessage = '',
    this.providerReceivedAt = '',
  });

  factory RealtimeArrival.fromJson(Map<String, Object?> json) {
    return RealtimeArrival(
      lineId: _string(json, 'lineId'),
      stationName: _string(json, 'stationName'),
      destination: _string(json, 'destination'),
      direction: _stringOrEmpty(json, 'direction'),
      trainNo: _stringOrEmpty(json, 'trainNo'),
      etaSeconds: _optionalInt(json, 'etaSeconds'),
      message: _stringOrEmpty(json, 'message'),
      positionMessage: _stringOrEmpty(json, 'positionMessage'),
      providerReceivedAt: _stringOrEmpty(json, 'providerReceivedAt'),
    );
  }

  final String lineId;
  final String stationName;
  final String destination;
  final String direction;
  final String trainNo;
  final int? etaSeconds;
  final String message;
  final String positionMessage;
  final String providerReceivedAt;
}

class RealtimeSnapshot {
  const RealtimeSnapshot({
    required this.status,
    this.fallbackCode = '',
    this.message = '',
    this.receivedAt = '',
    this.arrivals = const [],
  });

  const RealtimeSnapshot.loading()
    : status = RealtimeSnapshotStatus.loading,
      fallbackCode = '',
      message = '',
      receivedAt = '',
      arrivals = const [];

  const RealtimeSnapshot.unavailable()
    : status = RealtimeSnapshotStatus.unavailable,
      fallbackCode = 'PROVIDER_ERROR',
      message = '실시간 정보를 불러오지 못했어요. 역 정보와 경로 검색은 계속 이용할 수 있습니다.',
      receivedAt = '',
      arrivals = const [];

  factory RealtimeSnapshot.fromJson(Map<String, Object?> json) {
    final status = _statusFrom(_string(json, 'status'));
    final rawArrivals = json['arrivals'];
    return RealtimeSnapshot(
      status: status,
      fallbackCode: _stringOrEmpty(json, 'fallbackCode'),
      message: _stringOrEmpty(json, 'message'),
      receivedAt: _stringOrEmpty(json, 'receivedAt'),
      arrivals: rawArrivals is List<Object?>
          ? rawArrivals
                .whereType<Map<String, Object?>>()
                .map(RealtimeArrival.fromJson)
                .toList(growable: false)
          : const [],
    );
  }

  final RealtimeSnapshotStatus status;
  final String fallbackCode;
  final String message;
  final String receivedAt;
  final List<RealtimeArrival> arrivals;

  String get summaryText {
    if (arrivals.isEmpty) {
      return message;
    }
    final arrival = arrivals.first;
    return '${arrival.stationName} ${arrival.message}';
  }
}

abstract class RealtimeRepository {
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query);
}

class RealtimeApiRepository implements RealtimeRepository {
  RealtimeApiRepository({
    required this.baseUri,
    ApiClient? apiClient,
    HttpClient? httpClient,
  }) : _apiClient =
           apiClient ?? ApiClient(baseUri: baseUri, httpClient: httpClient);

  final Uri baseUri;
  final ApiClient _apiClient;

  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) async {
    final path = Uri(
      path: '/api/v1/realtime/arrivals',
      queryParameters: {
        'stationId': query.stationId,
        'lineId': query.lineId,
        if (query.providerLineId != null)
          'providerLineId': query.providerLineId,
        'stationQueryName': query.stationQueryName,
      },
    ).toString();
    try {
      final response = await _apiClient.getJson(path);
      final data = response.requireSuccessData(
        errorFactory: () => const RealtimeException('실시간 정보를 불러오지 못했어요.'),
        expectedStatusCode: HttpStatus.ok,
      );
      if (data is! Map<String, Object?>) {
        throw const RealtimeException('실시간 정보를 불러오지 못했어요.');
      }
      return RealtimeSnapshot.fromJson(data);
    } on RealtimeException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '실시간 도착 정보 조회 중 예외가 발생했습니다.',
      );
      throw const RealtimeException('실시간 정보를 불러오지 못했어요.');
    }
  }
}

class UnavailableRealtimeRepository implements RealtimeRepository {
  const UnavailableRealtimeRepository();

  @override
  Future<RealtimeSnapshot> arrivals(RealtimeStationQuery query) async {
    return const RealtimeSnapshot(
      status: RealtimeSnapshotStatus.unavailable,
      fallbackCode: 'PROVIDER_ERROR',
      message: '실시간 정보는 네트워크 연결 후 확인할 수 있습니다. 역 정보와 경로 검색은 계속 이용할 수 있습니다.',
    );
  }
}

class RealtimeException implements Exception {
  const RealtimeException(this.message);

  final String message;

  @override
  String toString() => message;
}

RealtimeSnapshotStatus _statusFrom(String status) {
  return switch (status) {
    'FRESH' => RealtimeSnapshotStatus.fresh,
    'STALE' => RealtimeSnapshotStatus.stale,
    'UNSUPPORTED' => RealtimeSnapshotStatus.unsupported,
    'UNAVAILABLE' => RealtimeSnapshotStatus.unavailable,
    _ => RealtimeSnapshotStatus.unavailable,
  };
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw const FormatException('Invalid realtime payload.');
}

String _stringOrEmpty(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? value : '';
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}
