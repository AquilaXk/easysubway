import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/facility_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('report-status golden fixture를 FacilityReportResult가 decode한다', () {
    final decoded =
        jsonDecode(
              File(
                '../../contracts/api/fixtures/report-status.ok.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;

    final data = decoded['data']! as Map<String, Object?>;

    final result = FacilityReportResult.fromJson(data);

    expect(result.id, '__REPORT_ID__');
    expect(result.stationId, 'station-sangnoksu');
    expect(result.facilityId, 'facility-sangnoksu-elevator-1');
    expect(result.reportType, 'BROKEN');
    expect(result.description, '엘리베이터 문이 열리지 않습니다.');
    expect(result.status, 'SUBMITTED');
    expect(result.createdAt, '__CREATED_AT__');
    expect(result.publicReceiptCode, '__PUBLIC_RECEIPT_CODE__');
  });

  test('report upload intent golden fixture를 mobile parser가 decode한다', () {
    final decoded =
        jsonDecode(
              File(
                '../../contracts/api/fixtures/report-upload-intent.created.json',
              ).readAsStringSync(),
            )
            as Map<String, Object?>;

    final intent = FacilityReportPhotoUploadIntent.fromJson(
      decoded,
      errorMessage: 'fixture parse failed',
    );

    expect(intent.objectKey, 'reports/__REPORT_UPLOAD_OBJECT_KEY__.jpg');
    expect(intent.uploadUrl, '/api/v1/report-uploads/__REPORT_UPLOAD_ID__');
    expect(intent.uploadMethod, 'PUT');
    expect(intent.uploadHeaders['content-type'], 'image/jpeg');
    expect(
      intent.uploadHeaders['x-easysubway-upload-sha256'],
      '2c8648d103e3dd7ad87660da0f126a1443b6d21ac1bd3ec000c5e24e2373a90c',
    );
    expect(intent.uploadHeaders['x-easysubway-upload-size'], '11');
  });
}
