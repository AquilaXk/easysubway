import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/auth_headers.dart';
import 'package:easysubway_mobile/facility_report.dart';
import 'package:easysubway_mobile/mobile_error_reporter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('시설 신고 사진 선택기는 복구된 사진을 첨부 데이터로 바꾼다', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'facility-report-photo-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final photoFile = File('${tempDir.path}/restored-photo.png');
    await photoFile.writeAsBytes([1, 2, 3, 4]);

    final picker = ImagePickerFacilityReportPhotoPicker(
      imagePicker: FakeLostDataImagePicker(
        LostDataResponse(
          file: XFile(photoFile.path, name: 'restored-photo.png'),
          type: RetrieveType.image,
        ),
      ),
    );

    final attachment = await picker.retrieveLostPhoto();

    expect(attachment, isNotNull);
    expect(attachment!.fileName, 'restored-photo.png');
    expect(attachment.contentType, 'image/png');
    expect(attachment.dataBase64, 'AQIDBA==');
  });

  test('시설 신고 사진 선택기는 복구할 사진이 없으면 첨부하지 않는다', () async {
    final picker = ImagePickerFacilityReportPhotoPicker(
      imagePicker: FakeLostDataImagePicker(LostDataResponse.empty()),
    );

    final attachment = await picker.retrieveLostPhoto();

    expect(attachment, isNull);
  });

  test('시설 신고 사진 선택기는 복구 오류를 쉬운 안내로 바꾼다', () async {
    final picker = ImagePickerFacilityReportPhotoPicker(
      imagePicker: FakeLostDataImagePicker(
        LostDataResponse(
          exception: PlatformException(code: 'lost_data_error'),
          type: RetrieveType.image,
        ),
      ),
    );

    await expectLater(
      picker.retrieveLostPhoto(),
      throwsA(
        isA<FacilityReportPhotoException>().having(
          (error) => error.message,
          'message',
          '사진을 다시 선택해 주세요.',
        ),
      ),
    );
  });

  test('시설 신고 API 저장소는 백엔드 계약에 맞춰 신고를 전송한다', () async {
    late String? authorizationHeader;
    late Map<String, Object?> requestBody;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      authorizationHeader = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
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
      authProvider: const BasicAuthorizationHeaderProvider(
        username: 'anonymous-user-1',
        password: 'user-test-password',
      ),
    );

    final result = await repository.createReport(
      const FacilityReportRequest(
        userId: 'anonymous-mobile-user',
        stationId: 'station-sangnoksu',
        facilityId: 'facility-sangnoksu-elevator-1',
        reportType: 'BROKEN',
        description: ' 문이 열리지 않습니다. ',
        photoFileName: 'elevator-door.jpg',
        photoContentType: 'image/jpeg',
        photoDataBase64: 'aW1hZ2UtYnl0ZXM=',
        latitude: 37.302421,
        longitude: 126.866221,
      ),
    );

    expect(requestBody['stationId'], 'station-sangnoksu');
    expect(requestBody['facilityId'], 'facility-sangnoksu-elevator-1');
    expect(requestBody['reportType'], 'BROKEN');
    expect(requestBody['description'], '문이 열리지 않습니다.');
    expect(requestBody['photoFileName'], 'elevator-door.jpg');
    expect(requestBody['photoContentType'], 'image/jpeg');
    expect(requestBody['photoDataBase64'], 'aW1hZ2UtYnl0ZXM=');
    expect(requestBody, isNot(contains('photoUrl')));
    expect(requestBody['latitude'], 37.302421);
    expect(requestBody['longitude'], 126.866221);
    expect(
      authorizationHeader,
      'Basic ${base64Encode(utf8.encode('anonymous-user-1:user-test-password'))}',
    );
    expect(result.id, 'report-1');
    expect(result.statusLabel, '접수됨');
  });

  test('시설 신고 요청은 사진이 없으면 사진 데이터를 전송하지 않는다', () {
    final request = const FacilityReportRequest(
      userId: 'anonymous-mobile-user',
      stationId: 'station-sangnoksu',
      facilityId: 'facility-sangnoksu-elevator-1',
      reportType: 'BROKEN',
      description: '문이 열리지 않습니다.',
    );

    expect(request.toJson(), isNot(contains('photoUrl')));
    expect(request.toJson(), isNot(contains('photoFileName')));
    expect(request.toJson(), isNot(contains('photoContentType')));
    expect(request.toJson(), isNot(contains('photoDataBase64')));
  });

  test('시설 신고 요청은 현재 위치가 없으면 좌표를 전송하지 않는다', () {
    final request = const FacilityReportRequest(
      userId: 'anonymous-mobile-user',
      stationId: 'station-sangnoksu',
      facilityId: 'facility-sangnoksu-elevator-1',
      reportType: 'BROKEN',
      description: '문이 열리지 않습니다.',
    );

    expect(request.toJson(), isNot(contains('latitude')));
    expect(request.toJson(), isNot(contains('longitude')));
  });

  test('시설 신고 API 저장소는 인증 실패 시 인증을 지우고 한 번 재시도한다', () async {
    final authorizationHeaders = <String?>[];
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      requestCount++;
      authorizationHeaders.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      await utf8.decodeStream(request);
      request.response.headers.contentType = ContentType.json;

      if (requestCount == 1) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write(jsonEncode({'success': false}))
          ..close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.created
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

    final authProvider = RetryAuthorizationHeaderProvider();
    final repository = FacilityReportApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: authProvider,
    );

    final result = await repository.createReport(
      const FacilityReportRequest(
        userId: 'anonymous-mobile-user',
        stationId: 'station-sangnoksu',
        facilityId: 'facility-sangnoksu-elevator-1',
        reportType: 'BROKEN',
        description: '문이 열리지 않습니다.',
      ),
    );

    expect(result.id, 'report-1');
    expect(authorizationHeaders, ['Basic stale-token', 'Basic fresh-token']);
    expect(authProvider.authorizationCount, 2);
    expect(authProvider.invalidateCount, 1);
  });

  test('시설 신고 API 저장소는 잘못된 접수 응답도 쉬운 실패 문구로 바꾼다', () async {
    final reportedErrors = _captureReportedErrors();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': {'id': 'report-1'},
          }),
        )
        ..close();
    });

    final repository = FacilityReportApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await expectLater(
        repository.createReport(
          const FacilityReportRequest(
            userId: 'anonymous-mobile-user',
            stationId: 'station-sangnoksu',
            facilityId: 'facility-sangnoksu-elevator-1',
            reportType: 'BROKEN',
            description: '문이 열리지 않습니다.',
          ),
        ),
        throwsA(
          isA<FacilityReportException>().having(
            (error) => error.message,
            'message',
            '신고를 보내지 못했습니다.',
          ),
        ),
      );
    });
    expect(reportedErrors, hasLength(1));
  });

  test('시설 신고 API 저장소는 파싱 실패 원인과 스택을 오류 경계에 보고한다', () async {
    final reportedErrors = _captureReportedErrors();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write('{broken-json')
        ..close();
    });

    final repository = FacilityReportApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    await runWithMobileErrorReporter(reportedErrors.add, () async {
      await expectLater(
        repository.createReport(
          const FacilityReportRequest(
            userId: 'anonymous-mobile-user',
            stationId: 'station-sangnoksu',
            facilityId: 'facility-sangnoksu-elevator-1',
            reportType: 'BROKEN',
            description: '문이 열리지 않습니다.',
          ),
        ),
        throwsA(
          isA<FacilityReportException>().having(
            (error) => error.message,
            'message',
            '신고를 보내지 못했습니다.',
          ),
        ),
      );
    });

    expect(reportedErrors, hasLength(1));
    expect(reportedErrors.single.exception, isA<FormatException>());
    expect(reportedErrors.single.stack, isNotNull);
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

  test('내 신고 API 저장소는 백엔드 계약에 맞춰 신고 목록을 조회한다', () async {
    late String requestMethod;
    late String requestPath;
    late String? authorizationHeader;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestMethod = request.method;
      requestPath = request.uri.path;
      authorizationHeader = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'success': true,
            'data': [
              {
                'id': 'report-2',
                'stationId': 'station-sangnoksu',
                'facilityId': 'facility-sangnoksu-elevator-1',
                'reportType': 'CLOSED',
                'description': '출입문이 막혀 있습니다.',
                'status': 'ACCEPTED',
                'createdAt': '2026-06-15T09:00:00',
              },
              {
                'id': 'report-1',
                'stationId': 'station-sangnoksu',
                'facilityId': 'facility-sangnoksu-elevator-2',
                'reportType': 'BROKEN',
                'description': '버튼이 눌리지 않습니다.',
                'status': 'SUBMITTED',
                'createdAt': '2026-06-14T09:00:00',
              },
            ],
          }),
        )
        ..close();
    });

    final repository = FacilityReportApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: const BasicAuthorizationHeaderProvider(
        username: 'anonymous-user-1',
        password: 'user-test-password',
      ),
    );

    final reports = await repository.listMyReports();

    expect(requestMethod, 'GET');
    expect(requestPath, '/api/v1/me/reports');
    expect(
      authorizationHeader,
      'Basic ${base64Encode(utf8.encode('anonymous-user-1:user-test-password'))}',
    );
    expect(reports, hasLength(2));
    expect(reports.first.id, 'report-2');
    expect(reports.first.statusLabel, '반영됨');
    expect(reports.last.statusLabel, '접수됨');
  });

  test('내 신고 API 저장소는 인증 실패 시 인증을 지우고 한 번 재시도한다', () async {
    final authorizationHeaders = <String?>[];
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      requestCount++;
      authorizationHeaders.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      request.response.headers.contentType = ContentType.json;

      if (requestCount == 1) {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..write(jsonEncode({'success': false}))
          ..close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..write(
          jsonEncode({
            'success': true,
            'data': [
              {
                'id': 'report-1',
                'stationId': 'station-sangnoksu',
                'facilityId': 'facility-sangnoksu-elevator-1',
                'reportType': 'BROKEN',
                'description': '문이 열리지 않습니다.',
                'status': 'SUBMITTED',
                'createdAt': '2026-06-13T10:00:00',
              },
            ],
          }),
        )
        ..close();
    });

    final authProvider = RetryAuthorizationHeaderProvider();
    final repository = FacilityReportApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
      authProvider: authProvider,
    );

    final reports = await repository.listMyReports();

    expect(reports.single.id, 'report-1');
    expect(authorizationHeaders, ['Basic stale-token', 'Basic fresh-token']);
    expect(authProvider.authorizationCount, 2);
    expect(authProvider.invalidateCount, 1);
  });

  test('시설 신고 API 저장소는 상태 조회 실패를 전용 안내 문구로 바꾼다', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'success': false}))
        ..close();
    });

    final repository = FacilityReportApiRepository(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );

    await expectLater(
      repository.getReport('report-1'),
      throwsA(
        isA<FacilityReportException>().having(
          (error) => error.message,
          'message',
          '처리 상태를 확인하지 못했습니다.',
        ),
      ),
    );
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

  test('시설 신고 컨트롤러는 상태 확인 실패에도 접수 결과를 유지한다', () async {
    final repository = FailingRefreshFacilityReportRepository();
    final controller = FacilityReportController(repository: repository);
    addTearDown(controller.dispose);

    await controller.submit(
      target: _reportTarget(),
      selectedType: FacilityReportTypeOption.broken,
      description: '문이 열리지 않습니다.',
    );

    await controller.refreshCurrentReport();

    expect(repository.loadedReportIds, ['report-1']);
    expect(controller.state.status, FacilityReportViewStatus.failure);
    expect(controller.state.message, '처리 상태를 확인하지 못했습니다.');
    expect(controller.state.result?.id, 'report-1');
    expect(controller.state.result?.statusLabel, '접수됨');
  });
}

class FakeLostDataImagePicker extends ImagePicker {
  FakeLostDataImagePicker(this.response);

  final LostDataResponse response;

  @override
  Future<LostDataResponse> retrieveLostData() async => response;
}

List<FlutterErrorDetails> _captureReportedErrors() {
  return <FlutterErrorDetails>[];
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

  @override
  Future<List<FacilityReportResult>> listMyReports() {
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

  @override
  Future<List<FacilityReportResult>> listMyReports() {
    throw UnimplementedError();
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

class FailingRefreshFacilityReportRepository
    implements FacilityReportRepository {
  final loadedReportIds = <String>[];

  @override
  Future<FacilityReportResult> createReport(FacilityReportRequest request) {
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
    return Future.error(const FacilityReportException('처리 상태를 확인하지 못했습니다.'));
  }

  @override
  Future<List<FacilityReportResult>> listMyReports() {
    throw UnimplementedError();
  }
}

class RetryAuthorizationHeaderProvider implements AuthorizationHeaderProvider {
  int authorizationCount = 0;
  int invalidateCount = 0;

  @override
  Future<String?> authorizationHeader() async {
    authorizationCount++;
    if (authorizationCount == 1) {
      return 'Basic stale-token';
    }
    return 'Basic fresh-token';
  }

  @override
  Future<void> invalidateAuthorization() async {
    invalidateCount++;
  }
}
