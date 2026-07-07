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

    expect(FacilityReportResult.fromJson(data).status, 'SUBMITTED');
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

    expect(intent.uploadMethod, 'PUT');
    expect(intent.uploadHeaders['content-type'], 'image/jpeg');
  });
}
