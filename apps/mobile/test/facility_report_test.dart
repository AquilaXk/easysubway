import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/facility_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('시설 신고 API 저장소는 백엔드 계약에 맞춰 신고를 전송한다', () async {
    late Map<String, Object?> requestBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestBody =
          jsonDecode(await utf8.decodeStream(request)) as Map<String, Object?>;
      request.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'id': 'report-1',
              'stationId': 'station-sangnoksu',
              'facilityId': 'facility-sangnoksu-elevator-1',
              'reportType': 'BROKEN',
              'description': '문이 열리지 않습니다.',
              'status': 'SUBMITTED',
              'createdAt': '2026-06-13T10:00:00',
            },
          }),
        )
        ..close();
    });

    final repository = FacilityReportApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final result = await repository.createReport(
      const FacilityReportRequest(
        userId: 'anonymous-mobile-user',
        stationId: 'station-sangnoksu',
        facilityId: 'facility-sangnoksu-elevator-1',
        reportType: 'BROKEN',
        description: ' 문이 열리지 않습니다. ',
      ),
    );

    expect(requestBody['stationId'], 'station-sangnoksu');
    expect(requestBody['facilityId'], 'facility-sangnoksu-elevator-1');
    expect(requestBody['reportType'], 'BROKEN');
    expect(requestBody['description'], '문이 열리지 않습니다.');
    expect(result.id, 'report-1');
    expect(result.statusLabel, '접수됨');
  });

  test('시설 신고 API 저장소는 접수번호로 처리 상태를 조회한다', () async {
    late String requestMethod;
    late String requestPath;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestMethod = request.method;
      requestPath = request.uri.path;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {
              'id': 'report-1',
              'stationId': 'station-sangnoksu',
              'facilityId': 'facility-sangnoksu-elevator-1',
              'reportType': 'BROKEN',
              'description': '문이 열리지 않습니다.',
              'status': 'ACCEPTED',
              'createdAt': '2026-06-13T10:00:00',
            },
          }),
        )
        ..close();
    });

    final repository = FacilityReportApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    final result = await repository.getReport('report-1');

    expect(requestMethod, 'GET');
    expect(requestPath, '/api/v1/reports/report-1');
    expect(result.id, 'report-1');
    expect(result.status, 'ACCEPTED');
    expect(result.statusLabel, '반영됨');
  });

  test('시설 신고 컨트롤러는 전송 중 중복 제출을 막고 성공 상태를 알린다', () async {
    final repository = PendingFacilityReportRepository();
    final controller = FacilityReportController(repository: repository);
    addTearDown(controller.dispose);

    final target = _reportTarget();
    final firstSubmit = controller.submit(
      target: target,
      selectedType: FacilityReportTypeOption.broken,
      description: '문이 열리지 않습니다.',
    );
    final secondSubmit = controller.submit(
      target: target,
      selectedType: FacilityReportTypeOption.closed,
      description: '다시 누른 요청',
    );

    expect(repository.requests, hasLength(1));
    expect(controller.state.status, FacilityReportViewStatus.loading);

    repository.complete();
    await firstSubmit;
    await secondSubmit;

    expect(repository.requests, hasLength(1));
    expect(controller.state.status, FacilityReportViewStatus.success);
    expect(controller.state.message, '신고가 접수되었습니다.');
  });

  test('시설 신고 컨트롤러는 접수 후 처리 상태를 다시 확인한다', () async {
    final repository = RefreshableFacilityReportRepository();
    final controller = FacilityReportController(repository: repository);
    addTearDown(controller.dispose);

    await controller.submit(
      target: _reportTarget(),
      selectedType: FacilityReportTypeOption.broken,
      description: '문이 열리지 않습니다.',
    );

    expect(controller.state.result?.statusLabel, '접수됨');

    final refresh = controller.refreshCurrentReport();

    expect(repository.loadedReportIds, ['report-1']);
    expect(controller.state.status, FacilityReportViewStatus.loading);
    expect(controller.state.message, '처리 상태 확인 중');
    expect(controller.state.result?.statusLabel, '접수됨');

    repository.completeRefresh();
    await refresh;

    expect(controller.state.status, FacilityReportViewStatus.success);
    expect(controller.state.message, '처리 상태를 확인했습니다.');
    expect(controller.state.result?.statusLabel, '반영됨');
  });
}

FacilityReportTarget _reportTarget() {
  return const FacilityReportTarget(
    stationId: 'station-sangnoksu',
    stationName: '상록수',
    facilityId: 'facility-sangnoksu-elevator-1',
    facilityName: '1번 출구 엘리베이터',
    facilityTypeLabel: '엘리베이터',
    facilityStatusLabel: '정상',
  );
}

class PendingFacilityReportRepository implements FacilityReportRepository {
  final requests = <FacilityReportRequest>[];
  final _completer = Completer<FacilityReportResult>();

  @override
  Future<FacilityReportResult> createReport(FacilityReportRequest request) {
    requests.add(request);
    return _completer.future;
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) {
    throw UnimplementedError();
  }

  void complete() {
    _completer.complete(
      const FacilityReportResult(
        id: 'report-1',
        stationId: 'station-sangnoksu',
        facilityId: 'facility-sangnoksu-elevator-1',
        reportType: 'BROKEN',
        description: '문이 열리지 않습니다.',
        status: 'SUBMITTED',
        createdAt: '2026-06-13T10:00:00',
      ),
    );
  }
}

class RefreshableFacilityReportRepository implements FacilityReportRepository {
  final requests = <FacilityReportRequest>[];
  final loadedReportIds = <String>[];
  Completer<FacilityReportResult>? _refreshCompleter;

  @override
  Future<FacilityReportResult> createReport(FacilityReportRequest request) {
    requests.add(request);
    return Future.value(
      const FacilityReportResult(
        id: 'report-1',
        stationId: 'station-sangnoksu',
        facilityId: 'facility-sangnoksu-elevator-1',
        reportType: 'BROKEN',
        description: '문이 열리지 않습니다.',
        status: 'SUBMITTED',
        createdAt: '2026-06-13T10:00:00',
      ),
    );
  }

  @override
  Future<FacilityReportResult> getReport(String reportId) {
    loadedReportIds.add(reportId);
    _refreshCompleter = Completer<FacilityReportResult>();
    return _refreshCompleter!.future;
  }

  void completeRefresh() {
    _refreshCompleter!.complete(
      const FacilityReportResult(
        id: 'report-1',
        stationId: 'station-sangnoksu',
        facilityId: 'facility-sangnoksu-elevator-1',
        reportType: 'BROKEN',
        description: '문이 열리지 않습니다.',
        status: 'ACCEPTED',
        createdAt: '2026-06-13T10:00:00',
      ),
    );
  }
}
