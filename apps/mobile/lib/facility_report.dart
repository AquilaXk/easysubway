import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

const _facilityReportTimeout = Duration(seconds: 8);
const _facilityReportErrorMessage = '신고를 보내지 못했습니다.';
const _anonymousReportUserId = 'anonymous-mobile-user';

abstract class FacilityReportRepository {
  Future<FacilityReportResult> createReport(FacilityReportRequest request);
}

class FacilityReportApiRepository implements FacilityReportRepository {
  FacilityReportApiRepository({required this.baseUri, HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _httpClient;

  @override
  Future<FacilityReportResult> createReport(
    FacilityReportRequest reportRequest,
  ) async {
    final uri = baseUri.resolve('/api/v1/reports');

    try {
      final request = await _httpClient
          .postUrl(uri)
          .timeout(_facilityReportTimeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(reportRequest.toJson()));

      final response = await request.close().timeout(_facilityReportTimeout);
      final body = await utf8
          .decodeStream(response)
          .timeout(_facilityReportTimeout);

      if (response.statusCode != HttpStatus.created &&
          response.statusCode != HttpStatus.ok) {
        throw const FacilityReportException(_facilityReportErrorMessage);
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, Object?> || decoded['success'] != true) {
        throw const FacilityReportException(_facilityReportErrorMessage);
      }

      final data = decoded['data'];
      if (data is! Map<String, Object?>) {
        throw const FacilityReportException(_facilityReportErrorMessage);
      }

      return FacilityReportResult.fromJson(data);
    } on FacilityReportException {
      rethrow;
    } catch (_) {
      throw const FacilityReportException(_facilityReportErrorMessage);
    }
  }
}

class FacilityReportException implements Exception {
  const FacilityReportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FacilityReportRequest {
  const FacilityReportRequest({
    required this.userId,
    required this.stationId,
    required this.facilityId,
    required this.reportType,
    required this.description,
  });

  final String userId;
  final String stationId;
  final String facilityId;
  final String reportType;
  final String description;

  FacilityReportRequest trimmed() {
    return FacilityReportRequest(
      userId: userId.trim(),
      stationId: stationId.trim(),
      facilityId: facilityId.trim(),
      reportType: reportType.trim(),
      description: description.trim(),
    );
  }

  Map<String, Object?> toJson() {
    final request = trimmed();
    return {
      'userId': request.userId,
      'stationId': request.stationId,
      'facilityId': request.facilityId,
      'reportType': request.reportType,
      'description': request.description,
    };
  }
}

class FacilityReportResult {
  const FacilityReportResult({
    required this.id,
    required this.stationId,
    required this.facilityId,
    required this.reportType,
    required this.description,
    required this.status,
    required this.createdAt,
  });

  factory FacilityReportResult.fromJson(Map<String, Object?> json) {
    return FacilityReportResult(
      id: _requiredReportString(json, 'id'),
      stationId: _requiredReportString(json, 'stationId'),
      facilityId: _requiredReportString(json, 'facilityId'),
      reportType: _requiredReportString(json, 'reportType'),
      description: _optionalReportString(json, 'description'),
      status: _requiredReportString(json, 'status'),
      createdAt: _requiredReportString(json, 'createdAt'),
    );
  }

  final String id;
  final String stationId;
  final String facilityId;
  final String reportType;
  final String description;
  final String status;
  final String createdAt;

  String get statusLabel {
    return switch (status) {
      'SUBMITTED' => '접수됨',
      'UNDER_REVIEW' => '확인 중',
      'ACCEPTED' => '반영됨',
      'REJECTED' => '반려됨',
      'DUPLICATE' => '중복 신고',
      'RESOLVED' => '처리 완료',
      _ => '접수 상태 확인 필요',
    };
  }
}

class FacilityReportTarget {
  const FacilityReportTarget({
    required this.stationId,
    required this.stationName,
    required this.facilityId,
    required this.facilityName,
    required this.facilityTypeLabel,
    required this.facilityStatusLabel,
  });

  final String stationId;
  final String stationName;
  final String facilityId;
  final String facilityName;
  final String facilityTypeLabel;
  final String facilityStatusLabel;
}

enum FacilityReportTypeOption {
  broken,
  underConstruction,
  closed,
  locationWrong,
  informationWrong,
  recovered,
}

extension FacilityReportTypeOptionLabel on FacilityReportTypeOption {
  String get reportType {
    return switch (this) {
      FacilityReportTypeOption.broken => 'BROKEN',
      FacilityReportTypeOption.underConstruction => 'UNDER_CONSTRUCTION',
      FacilityReportTypeOption.closed => 'CLOSED',
      FacilityReportTypeOption.locationWrong => 'LOCATION_WRONG',
      FacilityReportTypeOption.informationWrong => 'INFORMATION_WRONG',
      FacilityReportTypeOption.recovered => 'RECOVERED',
    };
  }

  String get label {
    return switch (this) {
      FacilityReportTypeOption.broken => '고장',
      FacilityReportTypeOption.underConstruction => '공사 중',
      FacilityReportTypeOption.closed => '폐쇄',
      FacilityReportTypeOption.locationWrong => '위치가 달라요',
      FacilityReportTypeOption.informationWrong => '정보가 달라요',
      FacilityReportTypeOption.recovered => '다시 정상',
    };
  }

  IconData get icon {
    return switch (this) {
      FacilityReportTypeOption.broken => Icons.warning_amber_rounded,
      FacilityReportTypeOption.underConstruction => Icons.construction,
      FacilityReportTypeOption.closed => Icons.block,
      FacilityReportTypeOption.locationWrong => Icons.wrong_location_outlined,
      FacilityReportTypeOption.informationWrong => Icons.edit_note,
      FacilityReportTypeOption.recovered => Icons.check_circle_outline,
    };
  }
}

enum FacilityReportViewStatus { idle, loading, success, failure }

class FacilityReportState {
  const FacilityReportState({
    required this.status,
    this.message = '',
    this.result,
  });

  const FacilityReportState.idle()
    : status = FacilityReportViewStatus.idle,
      message = '',
      result = null;

  final FacilityReportViewStatus status;
  final String message;
  final FacilityReportResult? result;
}

class FacilityReportController extends ChangeNotifier {
  FacilityReportController({required this.repository});

  final FacilityReportRepository repository;

  FacilityReportState _state = const FacilityReportState.idle();
  bool _disposed = false;

  FacilityReportState get state => _state;

  Future<void> submit({
    required FacilityReportTarget target,
    required FacilityReportTypeOption selectedType,
    required String description,
  }) async {
    if (_disposed || _state.status == FacilityReportViewStatus.loading) {
      return;
    }

    _emitState(
      const FacilityReportState(
        status: FacilityReportViewStatus.loading,
        message: '신고 보내는 중',
      ),
    );

    try {
      final result = await repository.createReport(
        FacilityReportRequest(
          userId: _anonymousReportUserId,
          stationId: target.stationId,
          facilityId: target.facilityId,
          reportType: selectedType.reportType,
          description: description,
        ),
      );
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.success,
          message: '신고가 접수되었습니다.',
          result: result,
        ),
      );
    } on FacilityReportException catch (error) {
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: error.message,
        ),
      );
    } catch (_) {
      _emitState(
        const FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: _facilityReportErrorMessage,
        ),
      );
    }
  }

  void _emitState(FacilityReportState nextState) {
    if (_disposed) {
      return;
    }
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class FacilityReportScreen extends StatefulWidget {
  const FacilityReportScreen({
    required this.repository,
    required this.target,
    super.key,
  });

  final FacilityReportRepository repository;
  final FacilityReportTarget target;

  @override
  State<FacilityReportScreen> createState() => _FacilityReportScreenState();
}

class _FacilityReportScreenState extends State<FacilityReportScreen> {
  late final FacilityReportController _controller;
  final TextEditingController _descriptionController = TextEditingController();
  FacilityReportTypeOption _selectedType = FacilityReportTypeOption.broken;

  @override
  void initState() {
    super.initState();
    _controller = FacilityReportController(repository: widget.repository)
      ..addListener(_onReportStateChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onReportStateChanged);
    _controller.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    final isLoading = state.status == FacilityReportViewStatus.loading;
    final isSuccess = state.status == FacilityReportViewStatus.success;

    return Scaffold(
      appBar: AppBar(title: const Text('시설 신고')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _FacilityReportHeader(target: widget.target),
            const SizedBox(height: 24),
            const _FacilityReportSectionTitle(title: '무엇을 알려드릴까요?'),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final option in FacilityReportTypeOption.values)
                      SizedBox(
                        width: cardWidth,
                        child: _FacilityReportTypeCard(
                          option: option,
                          selected: option == _selectedType,
                          onTap: isLoading || isSuccess
                              ? null
                              : () => setState(() => _selectedType = option),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('facilityReportDescriptionInput'),
              controller: _descriptionController,
              enabled: !isLoading && !isSuccess,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              style: const TextStyle(fontSize: 18, height: 1.35),
              decoration: const InputDecoration(
                labelText: '내용',
                hintText: '상황을 짧게 적어 주세요',
                floatingLabelBehavior: FloatingLabelBehavior.always,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (state.message.isNotEmpty) _FacilityReportMessage(state: state),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const Key('facilityReportSubmitButton'),
              onPressed: isLoading || isSuccess ? null : _submit,
              icon: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.send),
              label: Text(isSuccess ? '접수 완료' : '신고 보내기'),
            ),
          ],
        ),
      ),
    );
  }

  void _onReportStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _submit() {
    _controller.submit(
      target: widget.target,
      selectedType: _selectedType,
      description: _descriptionController.text,
    );
  }
}

class _FacilityReportHeader extends StatelessWidget {
  const _FacilityReportHeader({required this.target});

  final FacilityReportTarget target;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label:
          '${target.stationName}역, ${target.facilityName}, ${target.facilityTypeLabel}, 현재 ${target.facilityStatusLabel}',
      header: true,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${target.stationName}역',
              style: textTheme.headlineSmall?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              target.facilityName,
              style: textTheme.titleLarge?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${target.facilityTypeLabel} · ${target.facilityStatusLabel}',
              style: textTheme.bodyLarge?.copyWith(
                color: const Color(0xFF29484B),
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FacilityReportSectionTitle extends StatelessWidget {
  const _FacilityReportSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: const Color(0xFF102A2C),
          fontWeight: FontWeight.w900,
          height: 1.25,
        ),
      ),
    );
  }
}

class _FacilityReportTypeCard extends StatelessWidget {
  const _FacilityReportTypeCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final FacilityReportTypeOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF006D77) : const Color(0xFFD5E2E4);
    final textColor = selected ? Colors.white : const Color(0xFF102A2C);
    final semanticsLabel = '${option.label} ${selected ? '선택됨' : '선택 가능'}';

    return Semantics(
      label: semanticsLabel,
      button: true,
      selected: selected,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: selected ? color : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: color, width: 1.5),
          ),
          child: InkWell(
            key: Key('facilityReportType-${option.reportType}'),
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(option.icon, color: textColor, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        option.label,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w900,
                              height: 1.25,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FacilityReportMessage extends StatelessWidget {
  const _FacilityReportMessage({required this.state});

  final FacilityReportState state;

  @override
  Widget build(BuildContext context) {
    final isFailure = state.status == FacilityReportViewStatus.failure;
    final color = isFailure ? const Color(0xFF8A4B00) : const Color(0xFF006D77);
    final icon = isFailure ? Icons.error_outline : Icons.check_circle_outline;

    return Semantics(
      label: state.message,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.message,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFF102A2C),
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _requiredReportString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Missing required report field: $key');
}

String _optionalReportString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  return '';
}
