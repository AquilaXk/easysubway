import 'package:easysubway_mobile/mobility_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('이동 조건 선택지는 백엔드 이동 유형 값과 일치한다', () {
    final mobilityTypesById = {
      for (final option in mobilityProfileOptions)
        option.id: option.mobilityType,
    };

    expect(mobilityTypesById['elderly'], 'SENIOR');
    expect(mobilityTypesById['stroller'], 'STROLLER');
    expect(mobilityTypesById['wheelchair'], 'WHEELCHAIR');
    expect(mobilityTypesById['pregnant'], 'PREGNANT');
    expect(mobilityTypesById['injured'], 'TEMPORARY_INJURY');
    expect(mobilityTypesById['luggage'], 'LUGGAGE');
  });
}
