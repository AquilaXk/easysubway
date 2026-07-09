import 'dart:convert';
import 'dart:io';

import 'package:easysubway_mobile/core/datapack/data_pack_update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dart update policy defaults stay in sync with release JSON', () {
    final json =
        jsonDecode(
              File('release/datapack-update-policy.json').readAsStringSync(),
            )
            as Map<String, Object?>;

    expect(
      DataPackUpdatePolicyDefaults.manifestCheckOnResumeMinIntervalSeconds,
      json['manifestCheckOnResumeMinIntervalSeconds'],
    );
    expect(
      DataPackUpdatePolicyDefaults.retryBackoffSeconds,
      json['retryBackoffSeconds'],
    );
    expect(
      DataPackUpdatePolicyDefaults.retryMaxAttemptsPerSession,
      json['retryMaxAttemptsPerSession'],
    );
    expect(
      DataPackUpdatePolicyDefaults.expiryUrgentWindowDays,
      json['expiryUrgentWindowDays'],
    );
  });
}
