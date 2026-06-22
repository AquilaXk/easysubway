import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'mobile_error_reporter.dart';

const _internalRouteTimeout = Duration(seconds: 8);
const _internalRouteErrorMessage = '내부 이동 안내를 불러오지 못했습니다.';

abstract class InternalRouteRepository {
  Future<List<InternalRouteNode>> listRouteNodes(String stationId);

  Future<InternalRouteResult> searchInternalRoute(InternalRouteRequest request);
}

class InternalRouteApiRepository implements InternalRouteRepository {
  InternalRouteApiRepository({required this.baseUri, HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _httpClient;

  @override
  Future<List<InternalRouteNode>> listRouteNodes(String stationId) async {
    final uri = baseUri.resolve(
      '/api/v1/stations/${Uri.encodeComponent(stationId.trim())}/route-nodes',
    );

    try {
      final data = await _getData(uri);
      if (data is! List<Object?>) {
        throw const InternalRouteException(_internalRouteErrorMessage);
      }
      return data
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Invalid internal route node');
            }
            return InternalRouteNode.fromJson(item);
          })
          .toList(growable: false);
    } on InternalRouteException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 내부 이동 노드 API 응답 처리 중 예외가 발생했습니다.',
      );
      throw const InternalRouteException(_internalRouteErrorMessage);
    }
  }

  @override
  Future<InternalRouteResult> searchInternalRoute(
    InternalRouteRequest routeRequest,
  ) async {
    final uri = baseUri.resolve('/api/v1/routes/internal');

    try {
      final request = await _httpClient
          .postUrl(uri)
          .timeout(_internalRouteTimeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(routeRequest.toJson()));

      final data = await _readResponseData(request);
      if (data is! Map<String, Object?>) {
        throw const InternalRouteException(_internalRouteErrorMessage);
      }

      return InternalRouteResult.fromJson(data);
    } on InternalRouteException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '역 내부 이동 경로 API 응답 처리 중 예외가 발생했습니다.',
      );
      throw const InternalRouteException(_internalRouteErrorMessage);
    }
  }

  Future<Object?> _getData(Uri uri) async {
    final request = await _httpClient
        .getUrl(uri)
        .timeout(_internalRouteTimeout);
    return _readResponseData(request);
  }

  Future<Object?> _readResponseData(HttpClientRequest request) async {
    final response = await request.close().timeout(_internalRouteTimeout);
    final body = await utf8
        .decodeStream(response)
        .timeout(_internalRouteTimeout);

    if (response.statusCode != HttpStatus.ok) {
      throw const InternalRouteException(_internalRouteErrorMessage);
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['success'] != true) {
      throw const InternalRouteException(_internalRouteErrorMessage);
    }

    return decoded['data'];
  }
}

class InternalRouteException implements Exception {
  const InternalRouteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class InternalRouteRequest {
  const InternalRouteRequest({
    required this.stationId,
    required this.fromNodeId,
    required this.toNodeId,
    required this.mobilityType,
  });

  final String stationId;
  final String fromNodeId;
  final String toNodeId;
  final String mobilityType;

  static InternalRouteRequest? defaultForNodes({
    required String stationId,
    required String mobilityType,
    required List<InternalRouteNode> nodes,
  }) {
    final stationNodes = nodes
        .where((node) => node.stationId == stationId)
        .toList(growable: false);
    final fromNode = _firstNodeOfTypes(stationNodes, const [
      'ELEVATOR',
      'ENTRANCE',
      'EXIT',
    ]);
    final toNode = _firstNodeOfTypes(stationNodes, const [
      'FAREGATE',
      'PLATFORM',
      'CONCOURSE',
    ]);
    if (fromNode == null || toNode == null || fromNode.id == toNode.id) {
      return null;
    }
    return InternalRouteRequest(
      stationId: stationId,
      fromNodeId: fromNode.id,
      toNodeId: toNode.id,
      mobilityType: mobilityType,
    );
  }

  InternalRouteRequest trimmed() {
    return InternalRouteRequest(
      stationId: stationId.trim(),
      fromNodeId: fromNodeId.trim(),
      toNodeId: toNodeId.trim(),
      mobilityType: mobilityType,
    );
  }

  Map<String, Object?> toJson() {
    final request = trimmed();
    return {
      'stationId': request.stationId,
      'fromNodeId': request.fromNodeId,
      'toNodeId': request.toNodeId,
      'mobilityType': request.mobilityType,
    };
  }
}

class InternalRouteNode {
  const InternalRouteNode({
    required this.id,
    required this.stationId,
    required this.type,
    required this.name,
    required this.facilityId,
    required this.displayLabel,
  });

  factory InternalRouteNode.fromJson(Map<String, Object?> json) {
    return InternalRouteNode(
      id: _requiredInternalRouteString(json, 'id'),
      stationId: _requiredInternalRouteString(json, 'stationId'),
      type: _requiredInternalRouteString(json, 'type'),
      name: _requiredInternalRouteString(json, 'name'),
      facilityId: _optionalInternalRouteString(json, 'facilityId'),
      displayLabel: _requiredInternalRouteString(json, 'displayLabel'),
    );
  }

  final String id;
  final String stationId;
  final String type;
  final String name;
  final String facilityId;
  final String displayLabel;
}

class InternalRouteResult {
  const InternalRouteResult({
    required this.stationId,
    required this.stationName,
    required this.fromNodeId,
    required this.fromNodeName,
    required this.toNodeId,
    required this.toNodeName,
    required this.mobilityType,
    required this.status,
    required this.totalDistanceMeters,
    required this.totalEstimatedSeconds,
    required this.steps,
    required this.warnings,
    required this.blockedReasons,
  });

  factory InternalRouteResult.fromJson(Map<String, Object?> json) {
    final rawSteps = json['steps'];
    final rawWarnings = json['warnings'];
    final rawBlockedReasons = json['blockedReasons'];
    if (rawSteps is! List<Object?> ||
        rawWarnings is! List<Object?> ||
        rawBlockedReasons is! List<Object?>) {
      throw const FormatException('Invalid internal route payload');
    }

    return InternalRouteResult(
      stationId: _requiredInternalRouteString(json, 'stationId'),
      stationName: _requiredInternalRouteString(json, 'stationName'),
      fromNodeId: _requiredInternalRouteString(json, 'fromNodeId'),
      fromNodeName: _requiredInternalRouteString(json, 'fromNodeName'),
      toNodeId: _requiredInternalRouteString(json, 'toNodeId'),
      toNodeName: _requiredInternalRouteString(json, 'toNodeName'),
      mobilityType: _requiredInternalRouteString(json, 'mobilityType'),
      status: _requiredInternalRouteString(json, 'status'),
      totalDistanceMeters: _requiredInternalRouteInt(
        json,
        'totalDistanceMeters',
      ),
      totalEstimatedSeconds: _requiredInternalRouteInt(
        json,
        'totalEstimatedSeconds',
      ),
      steps: rawSteps
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException(
                'Invalid internal route step payload',
              );
            }
            return InternalRouteStep.fromJson(item);
          })
          .toList(growable: false),
      warnings: rawWarnings
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException(
                'Invalid internal route warning payload',
              );
            }
            return InternalRouteWarning.fromJson(item);
          })
          .toList(growable: false),
      blockedReasons: rawBlockedReasons
          .map((item) {
            if (item is! String || item.trim().isEmpty) {
              throw const FormatException(
                'Invalid internal route blocked reason',
              );
            }
            return item.trim();
          })
          .toList(growable: false),
    );
  }

  final String stationId;
  final String stationName;
  final String fromNodeId;
  final String fromNodeName;
  final String toNodeId;
  final String toNodeName;
  final String mobilityType;
  final String status;
  final int totalDistanceMeters;
  final int totalEstimatedSeconds;
  final List<InternalRouteStep> steps;
  final List<InternalRouteWarning> warnings;
  final List<String> blockedReasons;

  bool get isBlocked => status == 'BLOCKED' || blockedReasons.isNotEmpty;

  String get statusLabel {
    return switch (status) {
      'FOUND' => '내부 이동 경로를 찾았습니다',
      'BLOCKED' => '계단 없는 내부 이동 경로가 없습니다',
      _ => '내부 이동 확인이 필요합니다',
    };
  }

  String get summaryLabel => '$fromNodeName에서 $toNodeName까지';

  String get totalBurdenLabel {
    if (isBlocked) {
      return blockedReasons.isEmpty ? '이동 전 확인 필요' : blockedReasons.join(', ');
    }
    return '${_internalRouteSecondsLabel(totalEstimatedSeconds)} · ${_internalRouteDistanceLabel(totalDistanceMeters)}';
  }

  String get semanticLabel {
    final parts = <String>[
      '내부 이동 안내',
      statusLabel,
      summaryLabel,
      totalBurdenLabel,
    ];
    if (warnings.isNotEmpty) {
      parts.add('주의 ${warnings.map((warning) => warning.message).join(', ')}');
    }
    if (steps.isNotEmpty) {
      parts.add('이동 단계 ${steps.map((step) => step.semanticLabel).join(', ')}');
    }
    return parts.join(', ');
  }

  IconData get statusIcon =>
      isBlocked ? Icons.priority_high : Icons.check_circle;
}

class InternalRouteStep {
  const InternalRouteStep({
    required this.sequence,
    required this.edgeId,
    required this.fromNodeId,
    required this.fromNodeName,
    required this.toNodeId,
    required this.toNodeName,
    required this.edgeType,
    required this.distanceMeters,
    required this.estimatedSeconds,
    required this.includesStairs,
    required this.requiresElevator,
    required this.requiresEscalator,
    required this.slopeLevel,
    required this.widthLevel,
    required this.reliabilityScore,
    required this.guidance,
    this.fieldValidationStatus = 'UNKNOWN',
  });

  factory InternalRouteStep.fromJson(Map<String, Object?> json) {
    return InternalRouteStep(
      sequence: _requiredInternalRouteInt(json, 'sequence'),
      edgeId: _requiredInternalRouteString(json, 'edgeId'),
      fromNodeId: _requiredInternalRouteString(json, 'fromNodeId'),
      fromNodeName: _requiredInternalRouteString(json, 'fromNodeName'),
      toNodeId: _requiredInternalRouteString(json, 'toNodeId'),
      toNodeName: _requiredInternalRouteString(json, 'toNodeName'),
      edgeType: _requiredInternalRouteString(json, 'edgeType'),
      distanceMeters: _requiredInternalRouteInt(json, 'distanceMeters'),
      estimatedSeconds: _requiredInternalRouteInt(json, 'estimatedSeconds'),
      includesStairs: _requiredInternalRouteBool(json, 'includesStairs'),
      requiresElevator: _requiredInternalRouteBool(json, 'requiresElevator'),
      requiresEscalator: _requiredInternalRouteBool(json, 'requiresEscalator'),
      slopeLevel: _requiredInternalRouteInt(json, 'slopeLevel'),
      widthLevel: _requiredInternalRouteInt(json, 'widthLevel'),
      reliabilityScore: _requiredInternalRouteInt(json, 'reliabilityScore'),
      guidance: _requiredInternalRouteString(json, 'guidance'),
      fieldValidationStatus:
          _optionalInternalRouteString(json, 'fieldValidationStatus').isEmpty
          ? 'UNKNOWN'
          : _optionalInternalRouteString(json, 'fieldValidationStatus'),
    );
  }

  final int sequence;
  final String edgeId;
  final String fromNodeId;
  final String fromNodeName;
  final String toNodeId;
  final String toNodeName;
  final String edgeType;
  final int distanceMeters;
  final int estimatedSeconds;
  final bool includesStairs;
  final bool requiresElevator;
  final bool requiresEscalator;
  final int slopeLevel;
  final int widthLevel;
  final int reliabilityScore;
  final String guidance;
  final String fieldValidationStatus;

  String get title => '$fromNodeName에서 $toNodeName까지';

  String get burdenLabel {
    final labels = <String>[
      _internalRouteSecondsLabel(estimatedSeconds),
      _internalRouteDistanceLabel(distanceMeters),
      _internalRouteFieldValidationLabel(fieldValidationStatus),
      if (includesStairs) '계단 포함',
      if (requiresElevator) '엘리베이터 필요',
      if (requiresEscalator) '에스컬레이터 확인',
      if (reliabilityScore < 80) '추가 확인 필요',
    ];
    return labels.join(' · ');
  }

  String get semanticLabel =>
      '$sequence번 내부 이동, $title, $burdenLabel, $guidance';
}

class InternalRouteWarning {
  const InternalRouteWarning({required this.code, required this.message});

  factory InternalRouteWarning.fromJson(Map<String, Object?> json) {
    return InternalRouteWarning(
      code: _requiredInternalRouteString(json, 'code'),
      message: _requiredInternalRouteString(json, 'message'),
    );
  }

  final String code;
  final String message;
}

enum InternalRouteViewStatus { loading, success, failure }

class InternalRouteState {
  const InternalRouteState({
    required this.status,
    this.result,
    this.message = '',
  });

  const InternalRouteState.loading()
    : status = InternalRouteViewStatus.loading,
      result = null,
      message = '';

  final InternalRouteViewStatus status;
  final InternalRouteResult? result;
  final String message;
}

class InternalRouteController extends ChangeNotifier {
  InternalRouteController({required this.repository});

  final InternalRouteRepository repository;

  InternalRouteState _state = const InternalRouteState.loading();
  bool _disposed = false;

  InternalRouteState get state => _state;

  Future<void> loadDefault({
    required String stationId,
    required String mobilityType,
  }) async {
    _state = const InternalRouteState.loading();
    notifyListeners();

    try {
      final nodes = await repository.listRouteNodes(stationId);
      final request = InternalRouteRequest.defaultForNodes(
        stationId: stationId,
        mobilityType: mobilityType,
        nodes: nodes,
      );
      if (request == null) {
        if (_disposed) {
          return;
        }
        _state = const InternalRouteState(
          status: InternalRouteViewStatus.failure,
          message: '내부 이동 기준점을 아직 확인하지 못했습니다.',
        );
        notifyListeners();
        return;
      }
      if (_disposed) {
        return;
      }
      await load(request);
    } on InternalRouteException catch (error) {
      if (_disposed) {
        return;
      }
      _state = InternalRouteState(
        status: InternalRouteViewStatus.failure,
        message: error.message,
      );
      notifyListeners();
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '내부 이동 기본 안내 처리 중 예외가 발생했습니다.',
      );
      if (_disposed) {
        return;
      }
      _state = const InternalRouteState(
        status: InternalRouteViewStatus.failure,
        message: _internalRouteErrorMessage,
      );
      notifyListeners();
    }
  }

  Future<void> load(InternalRouteRequest request) async {
    if (_disposed) {
      return;
    }
    _state = const InternalRouteState.loading();
    notifyListeners();

    try {
      final result = await repository.searchInternalRoute(request);
      if (_disposed) {
        return;
      }
      _state = InternalRouteState(
        status: InternalRouteViewStatus.success,
        result: result,
      );
    } on InternalRouteException catch (error) {
      if (_disposed) {
        return;
      }
      _state = InternalRouteState(
        status: InternalRouteViewStatus.failure,
        message: error.message,
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '내부 이동 안내 화면 처리 중 예외가 발생했습니다.',
      );
      if (_disposed) {
        return;
      }
      _state = const InternalRouteState(
        status: InternalRouteViewStatus.failure,
        message: _internalRouteErrorMessage,
      );
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String _requiredInternalRouteString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing $key');
  }
  return value.trim();
}

int _requiredInternalRouteInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('Missing $key');
  }
  return value;
}

bool _requiredInternalRouteBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('Missing $key');
  }
  return value;
}

String _optionalInternalRouteString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    return '';
  }
  return value.trim();
}

InternalRouteNode? _firstNodeOfTypes(
  List<InternalRouteNode> nodes,
  List<String> types,
) {
  for (final type in types) {
    for (final node in nodes) {
      if (node.type == type) {
        return node;
      }
    }
  }
  return null;
}

String _internalRouteDistanceLabel(int distanceMeters) {
  if (distanceMeters < 1000) {
    return '${distanceMeters}m';
  }
  final kilometers = distanceMeters / 1000;
  if (distanceMeters % 1000 == 0) {
    return '${kilometers.toStringAsFixed(0)}km';
  }
  return '${kilometers.toStringAsFixed(1)}km';
}

String _internalRouteFieldValidationLabel(String fieldValidationStatus) {
  return switch (fieldValidationStatus) {
    'VERIFIED' => '현장 검증됨',
    'STALE' => '현장 재확인 필요',
    'UNKNOWN' => '현장 검증 전',
    _ => '현장 검증 전',
  };
}

String _internalRouteSecondsLabel(int seconds) {
  if (seconds < 60) {
    return '약 $seconds초';
  }
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  if (remainder == 0) {
    return '약 $minutes분';
  }
  return '약 $minutes분 $remainder초';
}
