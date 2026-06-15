import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'auth_headers.dart';
import 'mobile_error_reporter.dart';

const _facilityReportTimeout = Duration(seconds: 8);
const _facilityReportErrorMessage = '신고를 보내지 못했습니다.';
const _facilityReportStatusErrorMessage = '처리 상태를 확인하지 못했습니다.';
const _facilityReportListErrorMessage = '신고 내역을 불러오지 못했습니다.';
const _anonymousReportUserId = 'anonymous-mobile-user';

abstract class FacilityReportRepository {
  Future<FacilityReportResult> createReport(FacilityReportRequest request);

  Future<FacilityReportResult> getReport(String reportId);

  Future<List<FacilityReportResult>> listMyReports();
}

class FacilityReportApiRepository implements FacilityReportRepository {
  FacilityReportApiRepository({
    required this.baseUri,
    this.authProvider,
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  final Uri baseUri;
  final AuthorizationHeaderProvider? authProvider;
  final HttpClient _httpClient;

  @override
  Future<FacilityReportResult> createReport(
    FacilityReportRequest reportRequest,
  ) async {
    try {
      return await _postReportWithAuthorizationRetry(reportRequest);
    } on FacilityReportException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 접수 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FacilityReportException(_facilityReportErrorMessage);
    }
  }

  Future<FacilityReportResult> _postReportWithAuthorizationRetry(
    FacilityReportRequest reportRequest,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = await _httpClient
          .postUrl(baseUri.resolve('/api/v1/reports'))
          .timeout(_facilityReportTimeout);
      final authorizationHeader = await authProvider
          ?.authorizationHeader()
          .timeout(_facilityReportTimeout);
      if (authorizationHeader != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          authorizationHeader,
        );
      }
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(reportRequest.toJson()));

      final response = await request.close().timeout(_facilityReportTimeout);
      final body = await utf8
          .decodeStream(response)
          .timeout(_facilityReportTimeout);

      if (response.statusCode == HttpStatus.unauthorized &&
          authorizationHeader != null &&
          attempt == 0) {
        // 만료된 익명 인증은 비우고 새 인증으로 한 번만 다시 시도한다.
        await authProvider!.invalidateAuthorization().timeout(
          _facilityReportTimeout,
        );
        continue;
      }

      if (response.statusCode != HttpStatus.created &&
          response.statusCode != HttpStatus.ok) {
        throw const FacilityReportException(_facilityReportErrorMessage);
      }

      return _reportResultFromBody(
        body,
        errorMessage: _facilityReportErrorMessage,
      );
    }
    throw const FacilityReportException(_facilityReportErrorMessage);
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) async {
    final trimmedReportId = reportId.trim();
    if (trimmedReportId.isEmpty) {
      throw const FacilityReportException(_facilityReportStatusErrorMessage);
    }

    final uri = baseUri.resolve(
      '/api/v1/reports/${Uri.encodeComponent(trimmedReportId)}',
    );

    try {
      final request = await _httpClient
          .getUrl(uri)
          .timeout(_facilityReportTimeout);
      final response = await request.close().timeout(_facilityReportTimeout);

      if (response.statusCode != HttpStatus.ok) {
        throw const FacilityReportException(_facilityReportStatusErrorMessage);
      }

      final body = await utf8
          .decodeStream(response)
          .timeout(_facilityReportTimeout);
      return _reportResultFromBody(
        body,
        errorMessage: _facilityReportStatusErrorMessage,
      );
    } on FacilityReportException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 처리 상태 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FacilityReportException(_facilityReportStatusErrorMessage);
    }
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() async {
    try {
      return await _getMyReportsWithAuthorizationRetry();
    } on FacilityReportException {
      rethrow;
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '내 시설 신고 목록 응답 처리 중 예외가 발생했습니다.',
      );
      throw const FacilityReportException(_facilityReportListErrorMessage);
    }
  }

  Future<List<FacilityReportResult>>
  _getMyReportsWithAuthorizationRetry() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = await _httpClient
          .getUrl(baseUri.resolve('/api/v1/me/reports'))
          .timeout(_facilityReportTimeout);
      final authorizationHeader = await authProvider
          ?.authorizationHeader()
          .timeout(_facilityReportTimeout);
      if (authorizationHeader != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          authorizationHeader,
        );
      }

      final response = await request.close().timeout(_facilityReportTimeout);
      final body = await utf8
          .decodeStream(response)
          .timeout(_facilityReportTimeout);

      if (response.statusCode == HttpStatus.unauthorized &&
          authorizationHeader != null &&
          attempt == 0) {
        // 목록 조회도 접수와 같은 익명 인증을 쓰므로 만료 시 한 번만 갱신한다.
        await authProvider!.invalidateAuthorization().timeout(
          _facilityReportTimeout,
        );
        continue;
      }

      if (response.statusCode != HttpStatus.ok) {
        throw const FacilityReportException(_facilityReportListErrorMessage);
      }

      return _reportListFromBody(
        body,
        errorMessage: _facilityReportListErrorMessage,
      );
    }
    throw const FacilityReportException(_facilityReportListErrorMessage);
  }

  FacilityReportResult _reportResultFromBody(
    String body, {
    required String errorMessage,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['success'] != true) {
      throw FacilityReportException(errorMessage);
    }

    final data = decoded['data'];
    if (data is! Map<String, Object?>) {
      throw FacilityReportException(errorMessage);
    }

    return FacilityReportResult.fromJson(data);
  }

  List<FacilityReportResult> _reportListFromBody(
    String body, {
    required String errorMessage,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['success'] != true) {
      throw FacilityReportException(errorMessage);
    }

    final data = decoded['data'];
    if (data is! List<Object?>) {
      throw FacilityReportException(errorMessage);
    }

    return [
      for (final item in data)
        if (item is Map<String, Object?>)
          FacilityReportResult.fromJson(item)
        else
          throw FacilityReportException(errorMessage),
    ];
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

  String get reportTypeLabel {
    return switch (reportType) {
      'BROKEN' => '고장',
      'UNDER_CONSTRUCTION' => '공사 중',
      'CLOSED' => '폐쇄',
      'LOCATION_WRONG' => '위치가 달라요',
      'INFORMATION_WRONG' => '정보가 달라요',
      'RECOVERED' => '다시 정상',
      _ => '시설 신고',
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
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 화면 제출 처리 중 예외가 발생했습니다.',
      );
      _emitState(
        const FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: _facilityReportErrorMessage,
        ),
      );
    }
  }

  Future<void> refreshCurrentReport() async {
    final currentResult = _state.result;
    if (_disposed ||
        _state.status == FacilityReportViewStatus.loading ||
        currentResult == null) {
      return;
    }

    _emitState(
      FacilityReportState(
        status: FacilityReportViewStatus.loading,
        message: '처리 상태 확인 중',
        result: currentResult,
      ),
    );

    try {
      final result = await repository.getReport(currentResult.id);
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.success,
          message: '처리 상태를 확인했습니다.',
          result: result,
        ),
      );
    } on FacilityReportException catch (error) {
      // 상태 확인이 실패해도 사용자가 접수번호를 잃지 않도록 직전 결과는 유지한다.
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: error.message,
          result: currentResult,
        ),
      );
    } catch (error, stackTrace) {
      reportMobileError(
        error,
        stackTrace,
        context: '시설 신고 처리 상태 새로고침 중 예외가 발생했습니다.',
      );
      // 알 수 없는 오류도 같은 화면에서 다시 확인할 수 있게 접수 결과를 보존한다.
      _emitState(
        FacilityReportState(
          status: FacilityReportViewStatus.failure,
          message: '처리 상태를 확인하지 못했습니다.',
          result: currentResult,
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

class MyFacilityReportListScreen extends StatefulWidget {
  const MyFacilityReportListScreen({required this.repository, super.key});

  final FacilityReportRepository repository;

  @override
  State<MyFacilityReportListScreen> createState() =>
      _MyFacilityReportListScreenState();
}

class _MyFacilityReportListScreenState
    extends State<MyFacilityReportListScreen> {
  late Future<List<FacilityReportResult>> _reportsFuture;

  @override
  void initState() {
    super.initState();
    _reportsFuture = widget.repository.listMyReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 신고')),
      body: SafeArea(
        child: FutureBuilder<List<FacilityReportResult>>(
          future: _reportsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _MyReportLoading();
            }
            if (snapshot.hasError) {
              return _MyReportError(onRetry: _retry);
            }

            final reports = snapshot.data ?? const <FacilityReportResult>[];
            if (reports.isEmpty) {
              return const _MyReportEmpty();
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              itemCount: reports.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _MyReportListItem(report: reports[index]);
              },
            );
          },
        ),
      ),
    );
  }

  void _retry() {
    setState(() {
      _reportsFuture = widget.repository.listMyReports();
    });
  }
}

class _MyReportLoading extends StatelessWidget {
  const _MyReportLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '신고 내역 불러오는 중',
      liveRegion: true,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _MyReportEmpty extends StatelessWidget {
  const _MyReportEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          '접수한 신고가 없습니다.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class _MyReportError extends StatelessWidget {
  const _MyReportError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _facilityReportListErrorMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF102A2C),
                fontWeight: FontWeight.w900,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('myReportsRetryButton'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyReportListItem extends StatelessWidget {
  const _MyReportListItem({required this.report});

  final FacilityReportResult report;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final description = report.description.isEmpty
        ? report.reportTypeLabel
        : report.description;

    return Semantics(
      label: '내 신고, 접수번호 ${report.id}, ${report.statusLabel}, $description',
      button: false,
      child: ExcludeSemantics(
        child: DecoratedBox(
          key: Key('myReport-${report.id}'),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD5E2E4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        report.reportTypeLabel,
                        style: textTheme.titleMedium?.copyWith(
                          color: const Color(0xFF102A2C),
                          fontWeight: FontWeight.w900,
                          height: 1.25,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _MyReportStatusPill(label: report.statusLabel),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  description,
                  style: textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF102A2C),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _MyReportMetaText(label: '접수번호', value: report.id),
                    _MyReportMetaText(
                      label: '접수일',
                      value: _reportDateLabel(report.createdAt),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MyReportStatusPill extends StatelessWidget {
  const _MyReportStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE6F2F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C7C2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
            height: 1.2,
          ),
        ),
      ),
    );
  }
}

class _MyReportMetaText extends StatelessWidget {
  const _MyReportMetaText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label $value',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: const Color(0xFF29484B),
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    );
  }
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
    final reportResult = state.result;
    final hasSubmittedReport = reportResult != null;

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
                          onTap: isLoading || hasSubmittedReport
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
              enabled: !isLoading && !hasSubmittedReport,
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
            if (reportResult != null) ...[
              _FacilityReportStatusPanel(
                result: reportResult,
                isLoading: isLoading,
                onRefresh: _controller.refreshCurrentReport,
              ),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              key: const Key('facilityReportSubmitButton'),
              onPressed: isLoading || hasSubmittedReport ? null : _submit,
              icon: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Icon(Icons.send),
              label: Text(hasSubmittedReport ? '접수 완료' : '신고 보내기'),
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

class _FacilityReportStatusPanel extends StatelessWidget {
  const _FacilityReportStatusPanel({
    required this.result,
    required this.isLoading,
    required this.onRefresh,
  });

  final FacilityReportResult result;
  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE6F2F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C7C2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              // 접수번호와 상태를 한 문장으로 묶어 스크린리더가 상태 변화를 읽게 한다.
              label: '신고 접수번호 ${result.id}, 현재 상태 ${result.statusLabel}',
              liveRegion: true,
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FacilityReportStatusRow(label: '접수번호', value: result.id),
                    const SizedBox(height: 10),
                    _FacilityReportStatusRow(
                      label: '처리 상태',
                      value: result.statusLabel,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              key: const Key('facilityReportRefreshButton'),
              onPressed: isLoading ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              label: Text(isLoading ? '확인 중' : '처리 상태 확인'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FacilityReportStatusRow extends StatelessWidget {
  const _FacilityReportStatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            color: const Color(0xFF29484B),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: textTheme.titleMedium?.copyWith(
            color: const Color(0xFF102A2C),
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
      ],
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

String _reportDateLabel(String createdAt) {
  final parsed = DateTime.tryParse(createdAt);
  if (parsed == null) {
    return createdAt;
  }
  final month = parsed.month.toString().padLeft(2, '0');
  final day = parsed.day.toString().padLeft(2, '0');
  return '${parsed.year}.$month.$day';
}
